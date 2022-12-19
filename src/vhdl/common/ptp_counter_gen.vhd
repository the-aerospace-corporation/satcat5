--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Global counter generation for Precision Time Protocol (PTP)
--
-- SatCat5 timestamps are referenced to a global free-running counter.
-- Given a pair of closely-spaced reference clocks, this block generates
-- that free-running counter.  The output should be connected to every
-- PTP-enabled element in the design.
--
-- The optional ConfigBus interface allows runtime adjustments to the counter
-- rate.  This can be used for software-controlled PLLs.  If this feature is
-- not needed, leave the ConfigBus interface disconnected.  Otherwise, the
-- control register is a 32-bit signed integer N that offsets the time
-- increment by N / 2^32 nanoseconds:
--  * Tnom(nsec)        = 1e9 / VCLKA_HZ
--  * Toffset(nsec)     = Register value / 2^32
--  * Timestamp[n+1]    = Timestamp[n] + Tnom + Toffset
--
-- The typical increment rate is ~10 MHz, giving an overall drift-rate
-- resolution of 0.002 nanoseconds per second and a full-scale tuning
-- range of +/-50 kHz (0.5% = 5,000 ppm).
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.vernier_config;
use     work.ptp_types.all;

entity ptp_counter_gen is
    generic (
    VCONFIG     : vernier_config;
    DEVADDR     : integer := CFGBUS_ADDR_NONE;
    REGADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- Vernier reference clocks.
    vclka       : in  std_logic;
    vclkb       : in  std_logic;
    vreset_p    : in  std_logic := '0';
    -- Optional ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;
    -- Counter output.
    ref_time    : out port_timeref);
end ptp_counter_gen;

architecture ptp_counter_gen of ptp_counter_gen is

-- Internal counter uses a finer resolution than the final timestamp.
-- (Note: Scale here isn't intrinsically tied to ConfigBus word size,
--        but this is the finest we can set with a simple register.)
constant TFINE_SCALE    : integer := CFGBUS_WORD_SIZE;
constant TFINE_EXTRA    : integer := TFINE_SCALE - TSTAMP_SCALE;
constant TFINE_WIDTH    : integer := TSTAMP_WIDTH + TFINE_EXTRA;
subtype tfine_t is unsigned(TFINE_WIDTH-1 downto 0);

-- Calculate the nominal increment based on VCLKA_HZ.
-- (Note: Updates every other cycle --> Effective frequency is halved.)
constant ONE_SEC    : real := 1.0e9 * (2.0 ** TFINE_SCALE);
constant INCR_R     : real := 2.0 * ONE_SEC / VCONFIG.vclka_hz;
constant INCR_U     : tfine_t := r2u(INCR_R, TFINE_WIDTH);

-- Free-running counter state.
signal tnext    : std_logic := '0';
signal tstamp   : tfine_t := (others => '0');
signal cpu_incr : tfine_t := (others => '0');
signal cpu_word : cfgbus_word := (others => '0');

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
-- (Vivado explicitly DOES NOT allow such constraints to be set in the HDL.)
attribute satcat5_cross_clock_src : boolean;
attribute satcat5_cross_clock_src of tstamp : signal is true;

begin

-- Sanity check on clock configuration.
assert (VCONFIG.vclka_hz < VCONFIG.vclkb_hz and VCONFIG.vclkb_hz < 1.1*VCONFIG.vclka_hz)
    report "Invalid Vernier clock (A slightly slower than B)." severity error;

-- Drive main output.
ref_time.vclka  <= vclka;
ref_time.vclkb  <= vclkb;
ref_time.tnext  <= tnext;
ref_time.tstamp <= tstamp(tstamp'left downto TFINE_EXTRA);

-- Counter increments on every other VCLKA cycle.
-- Strobe "TNEXT" just before each update.
p_ctr : process(vclka)
begin
    if rising_edge(vclka) then
        if (vreset_p = '1') then
            tstamp <= (others => '0');
        elsif (tnext = '1') then
            tstamp <= tstamp + INCR_U + cpu_incr;
        end if;
        if (vreset_p = '1') then
            tnext <= '0';
        else
            tnext <= not tnext;
        end if;
    end if;
end process;

-- Rescale the CPU adjustment word.
cpu_incr <= unsigned(resize(signed(cpu_word), TFINE_WIDTH));

-- Optional ConfigBus register.
-- Note: This optimizes down to a constant zero if ConfigBus is disconnected.
u_cpu : cfgbus_register_sync
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR,
    WR_ATOMIC   => true,
    RSTVAL      => (others => '0'))
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    sync_clk    => vclka,
    sync_val    => cpu_word);

end ptp_counter_gen;
