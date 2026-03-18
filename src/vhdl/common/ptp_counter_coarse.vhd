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
-- the user clock domain.  The interface is designed to be drop-in
-- replacement of the "ptp_counter_verdact" block.  A wrapper block
-- "ptp_counter_sync" makes it easy to select either implementation.
--
-- The Vernier reference signal consists of:
--  * VCLKA: The clock used to generate TNEXT and TSTAMP, ~20 MHz typ.
--  * VCLKB: Not used in this implementation.
--  * TNEXT: Clock-enable strobe asserted on every other VCLKA cycle.
--  * TSTAMP: A 48-bit timestamp updated on each falling edge of TNEXT.
--
-- We would like to generate a collinear timestamp for each user clock
-- cycle.  The simplest method is latch the timestamp whenever it
-- changes, then extrapolate between such updates.  Since updates are
-- frequent (i.e., ~10 MHz typ), small differences between the expected
-- vs. actual value of the user clock have minimal impact.  The largest
-- source of error is the "nearest neighbor" sampling of the timestamp,
-- yielding a total error equal to +/- 1/2 of the user clock period.
-- If finer precision is required, see "ptp_counter_verdact".
--
-- The challenge is that the user clock is asynchronous to the reference.
-- As a result, some caution must be taken to avoid metastability and
-- clock-skew hazards.  The safest approach is to:
--  * Use a double-register metastability buffer on the TNEXT strobe,
--    sampling in the user clock domain.  This output is named SYNC_TNEXT.
--  * Use a double-register matched delay on the TSTAMP word.
--  * Update on the rising edge of the SYNC_TNEXT.  This gives the maximum
--    tolerance for clock skew between TNEXT and each of bit of TSTAMP.
--      tnext:  __----____----____----__
--      tstamp: 000000111111112222222233
--      sample:   ^       ^       ^
--
-- The double-register buffers introduce an delay of 2.0 to 3.0 user clock
-- cycles, depending on the relative clock phase.  If the two clocks are
-- independent free-running oscillators, then the distribution will be
-- pseudorandomly uniform, yielding an average of 2.5 user clock cycles.
-- In addition, the sampling on the rising edge of TNEXT introduces a
-- bias equal to the reference clock period (VCLKA_HZ).  These offsets
-- are compensated numerically.
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
    generic map(RISING_ONLY => true)
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

-- Latch the upstream timestamp, then extrapolate between updates.
-- Each update applies an offset for expected bias terms (see top of file).
p_cnt : process (user_clk)
    constant CTR_SYNC_DLY : tstamp_t :=
        get_tstamp_incr(real(USER_CLK_HZ) / 2.5) +  -- Avg 2.5 user clocks
        get_tstamp_incr(VCONFIG.VCLKA_HZ);          -- Plus one refclk cycle
begin
    if rising_edge(user_clk) then
        if (sync_tnext = '1') then
            -- Latch upstream timestamp, plus offsets.
            user_ctr_r <= sync_tstamp_d1 + ctr_offset + CTR_SYNC_DLY;
        else
            -- Increment at nominal user clock period.
            user_ctr_r <= user_ctr_r + CTR_PERIOD;
        end if;
    end if;
end process;

ctr_offset <= unsigned(resize(signed(cfg_offset), TSTAMP_WIDTH));

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
