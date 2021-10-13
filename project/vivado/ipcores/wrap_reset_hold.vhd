--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- Block diagram wrapper for "sync_reset"
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_primitives.sync_reset;

entity wrap_reset_hold is
    generic (
    RESET_HOLD  : natural);         -- Minimum reset duration, in clocks
    port (
    aresetn     : in  std_logic;    -- Async reset, active low
    clk         : in  std_logic;    -- Reference clock
    reset_p     : out std_logic;    -- Output reset, active high
    reset_n     : out std_logic);   -- Output reset, active low
end wrap_reset_hold;

architecture wrap_reset_hold of wrap_reset_hold is

signal in_reset_p   : std_logic;
signal out_reset_p  : std_logic;

begin

-- Polarity conversion
in_reset_p  <= not aresetn;
reset_n     <= not out_reset_p;
reset_p     <= out_reset_p;

-- Instantiate the platform-specific primitive.
u_rst : sync_reset
    generic map(HOLD_MIN => RESET_HOLD)
    port map(
    in_reset_p  => in_reset_p,
    out_reset_p => out_reset_p,
    out_clk     => clk);

end wrap_reset_hold;
