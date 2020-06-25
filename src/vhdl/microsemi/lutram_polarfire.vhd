--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- Generic LUTRAM for Microsemi Polarfire FPGAs.
--
-- For cross-platform support, other blocks in this design use generic
-- wrappers for vendor-specific memory structures that are difficult to
-- infer.  This file contains implementations for Microsemi Polarfire FPGAs.
--
-- Reads and writes are both synchronous.  Read data is available on
-- the clock cycle after address is presented.
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity lutram is
    generic (
    AWIDTH  : integer);     -- Supports 5, 6, 7
    port (
    clk     : in  std_logic;
    wraddr  : in  unsigned(AWIDTH-1 downto 0);
    wren    : in  std_logic;
    wrval   : in  std_logic;
    rdaddr  : in  unsigned(AWIDTH-1 downto 0);
    rdval   : out std_logic);
end lutram;

architecture polarfire of lutram is

signal rd_raw, rd_reg : std_logic := '0';
signal mem : std_logic_vector(2**AWIDTH-1 downto 0);

begin

p_ram : process(clk)
begin
    if rising_edge(clk) then
        if(wren) then
            mem(to_integer(wraddr)) <= wrval;
        end if;
        rdval <= mem(to_integer(rdaddr));
    end if;
end process;

end polarfire;
