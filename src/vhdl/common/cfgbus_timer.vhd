--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus-controlled multipurpose timer:
--
-- This block defines three ConfigBus registers:
--  Reg0 = Watchdog timer (Read/write)
--      This register controls an autonomous watchdog countdown.  The
--      countdown is decremented every clock cycle; when it reaches
--      zero, it requests a reset.  Typically this is used to reset
--      the host CPU, etc., in the event of a freeze.
--
--      By default, the watchdog can be paused by writing all '1's to
--      the register, and this is the initial state on reset.  Writing
--      any other value sets the countdown register to the designated
--      value, delaying the next restart.
--
--      If WDOG_PAUSE is disabled at build-time, the initial state gives
--      a one-second countdown before reset, and there is no special
--      consideration for the all '1's state.
--  Reg1 = CPU clock frequency (Read only)
--      Report the CPU clock frequency, in Hz.
--  Reg2 = Performance counter (Read only)
--      Counts clock cycles since release of ConfigBus reset.
--      This is useful for precise measurement of elapsed time.
--  Reg3 = External event timer (Read only, optional)
--      This register monitors an external input for changes.
--      On either the rising or falling edge of this signal (configurable
--      at build-time), it latches the value of the performance counter.
--      Read this register to obtain the time of the most recent event.
--      Example: Pulse-per-second time distribution.
--  Reg4 = Fixed interval timer (Read/write, optional)
--      This register sets the period for a fixed-interval timer.
--      Write any value to set the interval to N+1 clocks and reset countdown.
--      Reading this register reports the current interval setting.
--      On startup, the default period for this timer is one millisecond.
--  Reg5 = Interrupt control for timer (Read/write, optional)
--      Interrupt control for fixed interval timer (see cfgbus_common.vhd)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.sync_toggle2pulse;

entity cfgbus_timer is
    generic (
    DEVADDR     : integer;          -- ConfigBus address
    CFG_CLK_HZ  : integer;          -- ConfigBus clock, in Hz
    EVT_ENABLE  : boolean := true;  -- Enable the event timer?
    EVT_RISING  : boolean := true;  -- Which edge to latch?
    TMR_ENABLE  : boolean := true;  -- Enable fixed-interval timer?
    WDOG_PAUSE  : boolean := true); -- Allow watchdog to be paused?
    port (
    -- Watchdog reset
    wdog_resetp : out std_logic;

    -- External event signal, latched on either edge.
    ext_evt_in  : in  std_logic;

    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_timer;

architecture cfgbus_timer of cfgbus_timer is

constant REGADDR_WDOG   : cfgbus_regaddr := 0;
constant REGADDR_CLKHZ  : cfgbus_regaddr := 1;
constant REGADDR_PERF   : cfgbus_regaddr := 2;
constant REGADDR_EVENT  : cfgbus_regaddr := 3;
constant REGADDR_TMRLEN : cfgbus_regaddr := 4;
constant REGADDR_TMRIRQ : cfgbus_regaddr := 5;

subtype cfgbus_ctr is unsigned(CFGBUS_WORD_SIZE-1 downto 0);
constant PAUSED   : cfgbus_ctr := (others => '1');
constant ONE_SEC  : cfgbus_ctr := to_unsigned(CFG_CLK_HZ, CFGBUS_WORD_SIZE);
constant ONE_MSEC : cfgbus_ctr := to_unsigned(CFG_CLK_HZ/1000 - 1, CFGBUS_WORD_SIZE);

signal cfg_ack_lcl  : cfgbus_ack := cfgbus_idle;
signal cfg_ack_tmr  : cfgbus_ack := cfgbus_idle;
signal evt_strobe   : std_logic;
signal tmr_toggle   : std_logic := '0';
signal tmr_period   : cfgbus_ctr := ONE_MSEC;
signal wdog_rst_reg : std_logic := '0';

begin

-- Drive external signals.
wdog_resetp <= wdog_rst_reg;
cfg_ack     <= cfgbus_merge(cfg_ack_lcl, cfg_ack_tmr);

-- Edge-detection for the asynchronous event signal.
u_pps : sync_toggle2pulse
    generic map(
    RISING_ONLY  => EVT_RISING,
    FALLING_ONLY => not EVT_RISING)
    port map(
    in_toggle   => ext_evt_in,
    out_strobe  => evt_strobe,
    out_clk     => cfg_cmd.clk);

-- Optional fixed-interval timer.
gen_irq : if TMR_ENABLE generate
    u_irq : cfgbus_interrupt
        generic map(
        DEVADDR     => DEVADDR,
        REGADDR     => REGADDR_TMRIRQ)
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_ack_tmr,
        ext_toggle  => tmr_toggle);

    p_tmr : process(cfg_cmd.clk)
        variable tmr_ctr : cfgbus_ctr := ONE_MSEC;
    begin
        if rising_edge(cfg_cmd.clk) then
            -- Trigger interrupt each time countdown reaches zero.
            if (tmr_ctr = 0) then
                tmr_toggle <= not tmr_toggle;
            end if;

            -- Update timer state.
            if (cfg_cmd.reset_p = '1') then
                tmr_period  <= ONE_MSEC;
                tmr_ctr     := ONE_MSEC;
            elsif (cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR_TMRLEN)) then
                tmr_period  <= unsigned(cfg_cmd.wdata);
                tmr_ctr     := unsigned(cfg_cmd.wdata);
            elsif (tmr_ctr > 0) then
                tmr_ctr     := tmr_ctr - 1; -- Continue countdown
            else
                tmr_ctr     := tmr_period;  -- Rollover at zero
            end if;
        end if;
    end process;
end generate;

-- Main ConfigBus state machine:
p_timer : process(cfg_cmd.clk)
    variable wdog_ctr : cfgbus_ctr := ONE_SEC;
    variable perf_ctr : cfgbus_ctr := (others => '0');
    variable evt_ctr  : cfgbus_ctr := (others => '0');
begin
    if rising_edge(cfg_cmd.clk) then
        -- Respond to reads
        if (cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR_WDOG)) then
            cfg_ack_lcl <= cfgbus_reply(std_logic_vector(wdog_ctr));
        elsif (cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR_CLKHZ)) then
            cfg_ack_lcl <= cfgbus_reply(std_logic_vector(ONE_SEC));
        elsif (cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR_PERF)) then
            cfg_ack_lcl <= cfgbus_reply(std_logic_vector(perf_ctr));
        elsif (EVT_ENABLE and cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR_EVENT)) then
            cfg_ack_lcl <= cfgbus_reply(std_logic_vector(evt_ctr));
        elsif (TMR_ENABLE and cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR_TMRLEN)) then
            cfg_ack_lcl <= cfgbus_reply(std_logic_vector(tmr_period));
        else
            cfg_ack_lcl <= cfgbus_idle;
        end if;

        -- Latch the time of each event rising edge.
        if (cfg_cmd.reset_p = '1') then
            evt_ctr := (others => '0');
        elsif (EVT_ENABLE and evt_strobe = '1') then
            evt_ctr := perf_ctr;
        end if;

        -- Performance counter simply increments forever.
        if (cfg_cmd.reset_p = '1') then
            perf_ctr := (others => '0');
        else
            perf_ctr := perf_ctr + 1;
        end if;

        -- Writable watchdog timer with pause and auto-decrement.
        wdog_rst_reg <= bool2bit(wdog_ctr = 0);
        if (cfg_cmd.reset_p = '1' and WDOG_PAUSE) then
            wdog_ctr := PAUSED;                     -- Reset (paused)
        elsif (cfg_cmd.reset_p = '1') then
            wdog_ctr := ONE_SEC;                    -- Reset (one-second)
        elsif (cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR_WDOG)) then
            wdog_ctr := unsigned(cfg_cmd.wdata);    -- Direct write
        elsif (WDOG_PAUSE and wdog_ctr = PAUSED) then
            wdog_ctr := wdog_ctr;                   -- No change (paused)
        elsif (wdog_ctr > 0) then
            wdog_ctr := wdog_ctr - 1;               -- Countdown to zero
        end if;
    end if;
end process;

end cfgbus_timer;
