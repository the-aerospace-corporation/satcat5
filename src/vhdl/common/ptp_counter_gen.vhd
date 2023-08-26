--------------------------------------------------------------------------
-- Copyright 2022, 2023 The Aerospace Corporation
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
-- that free-running counter using "ptp_counter_free".  The output should
-- be connected to every PTP-enabled element in the design.
--
-- The optional ConfigBus interface allows runtime adjustments to the counter
-- rate.  See "ptp_counter_free" for details.
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

-- Free-running counter state.
signal tnext    : std_logic := '0';
signal tstamp   : tstamp_t;

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
-- (Vivado explicitly DOES NOT allow such constraints to be set in the HDL.)
attribute dont_touch : boolean;
attribute dont_touch of tstamp : signal is true;
attribute keep : boolean;
attribute keep of tstamp : signal is true;
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
ref_time.tstamp <= tstamp;

-- Free-running counter with optional ConfigBus tuning.
-- Effective counter rate is 1/2 VCLKA (TNEXT every other cycle).
u_ctr : entity work.ptp_counter_free
    generic map(
    REF_CLK_HZ  => VCONFIG.vclka_hz,
    REF_CLK_DIV => 2,
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR)
    port map(
    ref_clk     => vclka,
    ref_cken    => tnext,
    ref_ctr     => tstamp,
    reset_p     => vreset_p,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

end ptp_counter_gen;
