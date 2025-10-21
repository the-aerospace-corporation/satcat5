--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Coarse Cross-clock counter for Precision Time Protocol (PTP)
-- See also: ptp_counter_sync.vhd, ptp_counter_verdact.vhd
--
-- SatCat5 timestamps are referenced to a global free-running counter.
-- However, the global counter operates in its own time-domain.  This
-- block coarsely extrapolates an equivalent free-running counter in
-- the user clock domain.  Interface is designed to be drop-in 
-- replacement of the ptp_counter_sync block.
--
-- To accomplish this, the global reference is latched when available.
-- Output user counter is the sum of reference value with the period
-- of the user clock. 
--
-- Default parameters are tested for user clocks from 50-200 MHz.
--
-- An optional ConfigBus register can be used to add an adjustable time
-- offset to the output counter.  Scale matches PTP format (i.e., one
-- LSB = 1 / 2^16 nanoseconds).
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;

entity ptp_counter_coarse is
    generic (
    VCONFIG     : vernier_config;   -- Vernier configuration
    USER_CLK_HZ : positive;         -- User clock frequency (Hz)
    DEVADDR     : integer := CFGBUS_ADDR_NONE;
    REGADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- Global reference clocks and counter.
    ref_time    : in  port_timeref;
    -- Optional ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;
    -- User clock and local counter.
    -- (Deassert clock-enable to freeze output if desired.)
    user_clk    : in  std_logic;
    user_lock   : out std_logic;    -- Timestamp locked?
    user_ctr    : out tstamp_t;     -- Timestamp value
    user_rate   : out tstamp_t;     -- Timestamp increment
    user_freq   : out tfreq_t);     -- Normalized frequency
end ptp_counter_coarse;

architecture ptp_counter_coarse of ptp_counter_coarse is

constant CTR_PERIOD : tstamp_t := get_tstamp_incr(USER_CLK_HZ);

-- Generate and resynchronize reference signals.
signal sync_tnext   : std_logic;

-- Counter generation and unit conversions.
signal ctr_offset   : tstamp_t;

-- Output selection and registers.
signal user_ctr_r       : tstamp_t := TSTAMP_DISABLED;
signal sync_tstamp_d0   : tstamp_t := TSTAMP_DISABLED;
signal sync_tstamp_d1   : tstamp_t := TSTAMP_DISABLED;

-- ConfigBus interface.
signal cfg_offset   : cfgbus_word;

-- Force register duplication for tight routing of critical signals.
attribute async_reg : boolean;
attribute async_reg of sync_tstamp_d0 : signal is true;

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
-- (Vivado explicitly DOES NOT allow such constraints to be set in the HDL.)
attribute satcat5_cross_clock_dst : boolean;
attribute satcat5_cross_clock_dst of sync_tstamp_d0 : signal is true;

begin

-- Drive top-level outputs.
user_ctr    <= user_ctr_r;
user_freq   <= (others => '0');
user_rate   <= CTR_PERIOD;
user_lock   <= '1';

-- Sanity check on clock configuration.
assert (real(USER_CLK_HZ) > 2.0*VCONFIG.vclka_hz)
    report "User clock too slow, unsafe operation." severity error;

-- Watch for changes in the reference counter.
u_sync_tnext : sync_toggle2pulse
    generic map(FALLING_ONLY => true)
    port map(
    in_toggle   => ref_time.tnext,
    out_strobe  => sync_tnext,
    out_clk     => user_clk);

-- CDC registers
p_tstamp_sync: process (user_clk)
begin
    if rising_edge (user_clk) then
        sync_tstamp_d0 <= ref_time.tstamp;
        sync_tstamp_d1 <= sync_tstamp_d0;
    end if;
end process;

-- Compensate for delay from CDC registers (2.5 clocks average)
p_cnt : process (user_clk)
    constant CTR_SYNC_DLY : tstamp_t := get_tstamp_incr(USER_CLK_HZ/2) + get_tstamp_incr(USER_CLK_HZ*2);
begin
    if rising_edge(user_clk) then
        if (sync_tnext = '1') then
            user_ctr_r <= sync_tstamp_d1 + ctr_offset + CTR_SYNC_DLY;
        else
            user_ctr_r <= user_ctr_r + CTR_PERIOD;
        end if;
    end if;
end process;

ctr_offset  <= unsigned(resize(signed(cfg_offset), TSTAMP_WIDTH));

-- ConfigBus interface sets a fixed time-offset.
-- (Simplifies to constant zero if ConfigBus is disconnected or disabled.)
u_cfg_offset : cfgbus_register
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR,
    WR_ATOMIC   => true)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    reg_val     => cfg_offset);

end ptp_counter_coarse;
