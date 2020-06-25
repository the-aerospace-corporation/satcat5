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
-- Specialized memory structures for Xilinx FPGAs.
--
-- For cross-platform support, other blocks in this design use generic
-- wrappers for vendor-specific memory structures that are difficult to
-- infer.  This file contains implementations for Xilinx FPGAs.
--
-- Reads and writes are both synchronous.  Read data is available on
-- the clock cycle after address is presented.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
library unisim;
use     unisim.vcomponents.all;

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

architecture xilinx of lutram is

signal rd_raw, rd_reg : std_logic := '0';

begin

gen_w5 : if (AWIDTH = 5) generate
    RAM32X1D_inst : RAM32X1D
        port map (
        DPO     => rd_raw,
        SPO     => open,
        A0      => wraddr(0),
        A1      => wraddr(1),
        A2      => wraddr(2),
        A3      => wraddr(3),
        A4      => wraddr(4),
        D       => wrval,
        DPRA0   => rdaddr(0),
        DPRA1   => rdaddr(1),
        DPRA2   => rdaddr(2),
        DPRA3   => rdaddr(3),
        DPRA4   => rdaddr(4),
        WCLK    => clk,
        WE      => wren);
end generate;

gen_w6 : if (AWIDTH = 6) generate
    RAM64X1D_inst : RAM64X1D
        port map(
        DPO     => rd_raw,
        SPO     => open,
        A0      => wraddr(0),
        A1      => wraddr(1),
        A2      => wraddr(2),
        A3      => wraddr(3),
        A4      => wraddr(4),
        A5      => wraddr(5),
        D       => wrval,
        DPRA0   => rdaddr(0),
        DPRA1   => rdaddr(1),
        DPRA2   => rdaddr(2),
        DPRA3   => rdaddr(3),
        DPRA4   => rdaddr(4),
        DPRA5   => rdaddr(5),
        WCLK    => clk,
        WE      => wren);
end generate;

gen_w7 : if (AWIDTH = 7) generate
    RAM128X1D_inst : RAM128X1D
        port map (
        DPO     => rd_raw,
        SPO     => open,
        A       => std_logic_vector(wraddr),
        D       => wrval,
        DPRA    => std_logic_vector(rdaddr),
        WCLK    => clk,
        WE      => wren);
end generate;

-- Register for buffering async reads.
p_buff : process(clk)
begin
    if rising_edge(clk) then
        rd_reg <= rd_raw;
    end if;
end process;

rdval <= rd_reg;

end xilinx;
