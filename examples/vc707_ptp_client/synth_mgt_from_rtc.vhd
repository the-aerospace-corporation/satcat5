--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Synthesize various square-wave frequency references from a SatCat5 RTC.
--
-- Use a GTX quad as a single-bit blind-oversampled D/A at 10 GSPS.
-- The input reference is a real-time clock (see ptp_types.vhd), broken
-- into individual signals for use with Vivado block-diagram interfaces.
--
-- The RTC is re-synchronized to the GTX parallel clock using VERDACT,
-- allowing synthesis of phase-locked square waves at various frequencies:
--  * Port 0 = Software-controlled 1 Hz (PPS)
--  * Port 1 = Software-controlled 1 kHz
--  * Port 2 = Software-controlled 10 MHz
--  * Port 3 = Free-running 125 MHz
--
-- In the example design, the outputs are routed to the FMC connector.
-- The FMC connector also provides the 100 MHz MGT reference clock.
--
-- If available, the MGT's derived 125 MHz clock serves as the preferred
-- reference for the entire design, since it is typically sourced by a
-- high-stability OCXO. However, the FMC connector is optional; if it is
-- not provided, the MGT remains in shutdown but the rest of the design
-- must operate normally. To allow this, this block includes logic that
-- reverts "out_clk_125" to use "sys_clk_125" as needed.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.bufgmux;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;

entity synth_mgt_from_rtc is
    generic (
    CFG_ENABLE      : boolean;      -- Enable synthesizer configuration?
    CFG_DEV_ADDR    : integer;      -- ConfigBus address for switch
    PTP_REF_HZ      : positive;     -- Frequency of vernier reference
    PTP_TAU_MS      : integer;      -- Tracking time constant (msec)
    PTP_AUX_EN      : boolean;      -- Enable extra timestamp filter?
    RTC_REF_HZ      : positive;     -- Frequency of "rtc_clk"
    DEBUG_MODE      : boolean;      -- Output debug patterns only
    CLOCK_MODE      : string := "auto");    -- "auto", "ext", "sys"
    port (
    -- Vernier reference
    tref_vclka      : in  std_logic;
    tref_vclkb      : in  std_logic;
    tref_tnext      : in  std_logic;
    tref_tstamp     : in  std_logic_vector(47 downto 0);

    -- Real-time clock
    rtc_clk         : in  std_logic;
    rtc_sec         : in  std_logic_vector(47 downto 0);
    rtc_nsec        : in  std_logic_vector(31 downto 0);
    rtc_subns       : in  std_logic_vector(15 downto 0);

    -- ConfigBus interface
    cfg_clk         : in  std_logic;
    cfg_devaddr     : in  std_logic_vector(7 downto 0);
    cfg_regaddr     : in  std_logic_vector(9 downto 0);
    cfg_wdata       : in  std_logic_vector(31 downto 0);
    cfg_wstrb       : in  std_logic_vector(3 downto 0);
    cfg_wrcmd       : in  std_logic;
    cfg_rdcmd       : in  std_logic;
    cfg_reset_p     : in  std_logic;
    cfg_rdata       : out std_logic_vector(31 downto 0);
    cfg_rdack       : out std_logic;
    cfg_rderr       : out std_logic;
    cfg_irq         : out std_logic;

    -- Optional diagnostics
    debug1_clk      : out std_logic;
    debug1_flag     : out std_logic_vector(7 downto 0);
    debug1_time     : out std_logic_vector(47 downto 0);
    debug2_clk      : out std_logic;
    debug2_flag     : out std_logic_vector(7 downto 0);
    debug2_time     : out std_logic_vector(47 downto 0);

    -- System clock and reset.
    sys_clk_125     : in  std_logic;    -- Always-running 125 MHz clock
    sys_reset_p     : in  std_logic;    -- External reset button
    out_clk_125     : out std_logic;    -- System clock output
    out_reset_p     : out std_logic;    -- System reset output
    out_detect      : out std_logic;    -- Detected external clock?
    out_select      : out std_logic;    -- Using external clock?

    -- MGT input and output.
    mgt_refclk_p    : in  std_logic;
    mgt_refclk_n    : in  std_logic;
    mgt_synth_p     : out std_logic_vector(3 downto 0);
    mgt_synth_n     : out std_logic_vector(3 downto 0));
end synth_mgt_from_rtc;

architecture synth_mgt_from_rtc of synth_mgt_from_rtc is

constant MGT_MSB1ST : boolean := false;
constant MGT_PAR_CT : positive := 80;
constant MGT_PAR_HZ : positive := 125_000_000;

constant VCONFIG : vernier_config :=
    create_vernier_config(PTP_REF_HZ, real(PTP_TAU_MS), PTP_AUX_EN);

subtype parallel_t is std_logic_vector(MGT_PAR_CT-1 downto 0);

signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal cfg_acks     : cfgbus_ack_array(0 to 1);
signal ref_time     : port_timeref;
signal rtc_time     : ptp_time_t;
signal rtc_tstamp   : tstamp_t;
signal rtc_reset    : std_logic;
signal mgt_clk      : std_logic;
signal mgt_config   : cfgbus_word;
signal mgt_rst_req  : std_logic;
signal mgt_rst_core : std_logic;
signal mgt_rst_test : std_logic;
signal mgt_rst_rtc  : std_logic;
signal mgt_rst_vref : std_logic;
signal mgt_time     : ptp_time_t;
signal mgt_tstamp   : tstamp_t;
signal mgt_tsync    : tstamp_t;
signal mgt_synth0   : parallel_t;
signal mgt_synth1   : parallel_t;
signal mgt_synth2   : parallel_t;
signal mgt_synth3   : parallel_t;
signal mux_detect   : std_logic;
signal mux_select   : std_logic;
signal mux_wait     : std_logic;
signal mux_wait_d   : std_logic;

begin

-- Repack the raw input signals into their preferred format.
ref_time.vclka  <= tref_vclka;
ref_time.vclkb  <= tref_vclkb;
ref_time.tnext  <= tref_tnext;
ref_time.tstamp <= unsigned(tref_tstamp);
rtc_time.sec    <= signed(rtc_sec);
rtc_time.nsec   <= unsigned(rtc_nsec);
rtc_time.subns  <= unsigned(rtc_subns);

-- Convert ConfigBus signals.
cfg_cmd.clk     <= cfg_clk;
cfg_cmd.sysaddr <= 0;   -- Unused
cfg_cmd.devaddr <= u2i(cfg_devaddr);
cfg_cmd.regaddr <= u2i(cfg_regaddr);
cfg_cmd.wdata   <= cfg_wdata;
cfg_cmd.wstrb   <= cfg_wstrb;
cfg_cmd.wrcmd   <= cfg_wrcmd;
cfg_cmd.rdcmd   <= cfg_rdcmd;
cfg_cmd.reset_p <= cfg_reset_p;
cfg_ack         <= cfgbus_merge(cfg_acks);
cfg_rdata       <= cfg_ack.rdata;
cfg_rdack       <= cfg_ack.rdack;
cfg_rderr       <= cfg_ack.rderr;
cfg_irq         <= cfg_ack.irq;

-- Extended reset signal for the MGT.
u_reset_req : sync_reset
    generic map(HOLD_MIN => 125_000)    -- 1 msec @ 125 MHz
    port map (
    in_reset_p  => sys_reset_p,         -- External button
    out_reset_p => mgt_rst_req,         -- Request to MGT
    out_clk     => sys_clk_125);        -- Always running

-- Extended wait and reset signals for clock failover (see below).
u_reset_mux : sync_reset
    generic map(HOLD_MIN => 1_250_000)  -- 10 msec @ 125 MHz
    port map (
    in_reset_p  => mgt_rst_req,         -- Request to MGT
    out_reset_p => mgt_rst_test,        -- Request to clock-test
    out_clk     => sys_clk_125);        -- Always running

-- Reset for VREF- and RTC-related logic must wait for stable MGT, RTC,
-- and VREF clocks.  (This may never occur if there is no MGT clock.)
mgt_rst_rtc <= mgt_rst_req or mgt_rst_core or not mux_detect;

u_reset_core : sync_reset
    generic map(HOLD_MIN => 1_250_000)  -- 10 msec @ 125 MHz
    port map (
    in_reset_p  => mgt_rst_rtc,         -- Status from MGT core
    out_reset_p => mgt_rst_vref,        -- Reset to VREF logic
    out_clk     => mgt_clk);            -- Optional clock

u_reset_rtc : sync_reset
    generic map(HOLD_MIN => 200_000)    -- 10 msec @ 20 MHz
    port map (
    in_reset_p  => mgt_rst_rtc,         -- Status from MGT core
    out_reset_p => rtc_reset,           -- Reset to RTC logic
    out_clk     => rtc_clk);            -- Derived from "out_clk_125"

-- Generate colinear timestamps for each clock of interest.
-- The MGT timestamp has a ConfigBus-adjustable offset parameter.
u_sync_rtc : entity work.ptp_counter_sync
    generic map(
    VCONFIG     => VCONFIG,
    USER_CLK_HZ => RTC_REF_HZ)
    port map(
    diagnostics => debug1_flag,
    ref_time    => ref_time,
    user_clk    => rtc_clk,
    user_ctr    => rtc_tstamp,
    user_rst_p  => rtc_reset);

u_sync_mgt : entity work.ptp_counter_sync
    generic map(
    DEVADDR     => cfgbus_devaddr_if(CFG_DEV_ADDR, CFG_ENABLE),
    REGADDR     => 0,
    VCONFIG     => VCONFIG,
    USER_CLK_HZ => MGT_PAR_HZ)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(0),
    diagnostics => debug2_flag,
    ref_time    => ref_time,
    user_clk    => mgt_clk,
    user_ctr    => mgt_tstamp,
    user_rst_p  => mgt_rst_vref);

-- Other ConfigBus registers.
u_cfg_gtx : cfgbus_register
    generic map(
    DEVADDR     => cfgbus_devaddr_if(CFG_DEV_ADDR, CFG_ENABLE),
    REGADDR     => 1,
    WR_ATOMIC   => true,
    WR_MASK     => (others => '1'),
    RSTVAL      => (others => '1'))
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(1),
    reg_val     => mgt_config);

-- Resynchronize the RTC into the GTX parallel clock domain.
u_realsync : entity work.ptp_realsync
    generic map(OUT_CLK_HZ => MGT_PAR_HZ)
    port map(
    ref_clk     => rtc_clk,
    ref_tstamp  => rtc_tstamp,
    ref_rtc     => rtc_time,
    out_clk     => mgt_clk,
    out_tstamp  => mgt_tstamp,
    out_rtc     => mgt_time);

-- Diagnostic copy of before/after RTC signals.
debug1_clk  <= rtc_clk;
debug1_time <= std_logic_vector(rtc_time.nsec & rtc_time.subns);
debug2_clk  <= mgt_clk;
debug2_time <= std_logic_vector(mgt_time.nsec & mgt_time.subns);

-- Synchronized timestamp, modulo one second.
mgt_tsync <= mgt_time.nsec & mgt_time.subns;

-- The first three GTX lanes each synthesize a phase-locked square-wave.
gen_clksynth : if not DEBUG_MODE generate
    u_synth0 : entity work.ptp_clksynth
        generic map(
        SYNTH_HZ    => 1,
        PAR_CLK_HZ  => MGT_PAR_HZ,
        PAR_COUNT   => MGT_PAR_CT,
        REF_MOD_HZ  => 1,
        MSB_FIRST   => MGT_MSB1ST)
        port map(
        par_clk     => mgt_clk,
        par_tstamp  => mgt_tsync,
        par_out     => mgt_synth0,
        reset_p     => mgt_rst_vref);

    u_synth1 : entity work.ptp_clksynth
        generic map(
        SYNTH_HZ    => 1_000,
        PAR_CLK_HZ  => MGT_PAR_HZ,
        PAR_COUNT   => MGT_PAR_CT,
        REF_MOD_HZ  => 1,
        MSB_FIRST   => MGT_MSB1ST)
        port map(
        par_clk     => mgt_clk,
        par_tstamp  => mgt_tsync,
        par_out     => mgt_synth1,
        reset_p     => mgt_rst_vref);

    u_synth2 : entity work.ptp_clksynth
        generic map(
        SYNTH_HZ    => 10_000_000,
        PAR_CLK_HZ  => MGT_PAR_HZ,
        PAR_COUNT   => MGT_PAR_CT,
        REF_MOD_HZ  => 1,
        MSB_FIRST   => MGT_MSB1ST)
        port map(
        par_clk     => mgt_clk,
        par_tstamp  => mgt_tsync,
        par_out     => mgt_synth2,
        reset_p     => mgt_rst_vref);
end generate;

-- Alternate debug mode uses simpler fixed patterns.
gen_clkdebug : if DEBUG_MODE generate
    -- 5 GHz square wave
    mgt_synth0 <= "0101010101010101010101010101010101010101"
                & "0101010101010101010101010101010101010101";
    -- 625 MHz square wave
    mgt_synth1 <= "0000000011111111000000001111111100000000"
                & "1111111100000000111111110000000011111111";
    -- Chirp pattern
    mgt_synth2 <= "0000000000001111111111100000000001111111"
                & "1100000000111111100000011111000011100101";
end generate;

-- The fourth GTX lane is a free-running 125 MHz square wave.
-- (Since this matches the parallel rate, this is a trivial fixed pattern.)
mgt_synth3 <= "1111111111111111111111111111111111111111"
            & "0000000000000000000000000000000000000000";

-- Instantiate wrapper for the GTX quad.
u_mgt : entity work.synth_mgt_wrapper
    generic map(PAR_WIDTH => MGT_PAR_CT)
    port map(
    free_clk    => sys_clk_125,
    reset_req_p => mgt_rst_req,
    reset_out_p => mgt_rst_core,
    tx_diffctrl => mgt_config(3 downto 0),
    par_clk     => mgt_clk,
    par_lane0   => mgt_synth0,
    par_lane1   => mgt_synth1,
    par_lane2   => mgt_synth2,
    par_lane3   => mgt_synth3,
    refclk_n    => mgt_refclk_n,
    refclk_p    => mgt_refclk_p,
    pin_tx_n    => mgt_synth_n,
    pin_tx_p    => mgt_synth_p);

-- MGT clock may operate erratically even if no external clock is applied,
-- so we apply an accuracy test.  Test begins shortly after "mgt_rst_req"
-- is released, whether or not MGT indicates it is ready.
u_tol : entity work.io_clock_tolerance
    generic map(
    REF_CLK_HZ  => 125_000_000,
    TST_CLK_HZ  => 125_000_000)
    port map(
    reset_p     => mgt_rst_test,
    ref_clk     => sys_clk_125,
    tst_clk     => mgt_clk,
    out_pass    => mux_detect,
    out_wait    => mux_wait);

-- Apply overrides if enabled.
mux_select <= '1' when CLOCK_MODE = "ext" else  -- External clock
              '0' when CLOCK_MODE = "sys" else  -- System clock
              mux_detect;                       -- Auto-detect (default)

-- Short delay for the outgoing reset.
u_reset_out : sync_reset
    generic map(HOLD_MIN => 255)        -- << 1 msec @ 125 MHz
    port map (
    in_reset_p  => mux_wait,            -- Clock test finished?
    out_reset_p => mux_wait_d,          -- Main system reset
    out_clk     => sys_clk_125);        -- Always running

-- Clock selection and drive final outputs.
u_select : bufgmux
    port map(
    I0  => sys_clk_125,
    I1  => mgt_clk,
    S   => mux_select,
    O   => out_clk_125);

out_detect  <= mux_detect;
out_select  <= mux_select;
out_reset_p <= mux_wait_d;

end synth_mgt_from_rtc;
