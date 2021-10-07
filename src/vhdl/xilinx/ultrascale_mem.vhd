--------------------------------------------------------------------------
-- Copyright 2020, 2021 The Aerospace Corporation
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
-- Inferred and explicit memory structures for Xilinx FPGAs.
--
-- This file implements the components defined in "common_primitives", using
-- explicit components and inference templates for Xilinx Ultrascale(+) FPGAs.
--
-- NOTE: Designs should only include ONE such implementation!  If your
-- project includes "xilinx/ultrascale_mem.vhd", don't also include similar
-- files from the "lattice" or "microsemi" folder.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_primitives.all;

-- Deferred constant definition(s):
package body common_primitives is
    -- RAM64X1D is a single slice (LUT6) and supports 6-bit addresses.
    constant PREFER_DPRAM_AWIDTH : positive := 6;
end package body;

---------------------------------------------------------------------

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;

entity infer_dpram is
    generic (
    AWIDTH  : positive;             -- Address width (bits)
    DWIDTH  : positive;             -- Data width (bits)
    SIMTEST : boolean := false;     -- Formal verification mode?
    TRIPORT : boolean := false);    -- Enable "wr_rval" port?
    port (
    wr_clk  : in  std_logic;
    wr_addr : in  unsigned(AWIDTH-1 downto 0);
    wr_en   : in  std_logic;
    wr_val  : in  std_logic_vector(DWIDTH-1 downto 0);
    wr_rval : out std_logic_vector(DWIDTH-1 downto 0);
    rd_clk  : in  std_logic;
    rd_addr : in  unsigned(AWIDTH-1 downto 0);
    rd_en   : in  std_logic := '1';
    rd_val  : out std_logic_vector(DWIDTH-1 downto 0));
end infer_dpram;

architecture infer_dpram of infer_dpram is

subtype word_t is std_logic_vector(DWIDTH-1 downto 0);
type dp_ram_t is array(0 to 2**AWIDTH-1) of word_t;
shared variable dp_ram : dp_ram_t := (others => (others => '0'));
signal wr_reg, rd_reg : word_t := (others => '0');

begin

-- Drive top-level outputs.
wr_rval <= wr_reg;
rd_val  <= rd_reg;

-- Inferred dual-port block RAM.
-- Note: "Three-port" mode is supported on 7-Series at no additional cost.
-- Note: We arbitrarily select "write-before-read" for the three-port mode.
p_ram_in : process(wr_clk)
begin
    if rising_edge(wr_clk) then
        if (wr_en = '1') then
            dp_ram(to_integer(wr_addr)) := wr_val;
        end if;
        if (SIMTEST and wr_en = '1') then
            wr_reg <= (others => 'X');  -- Undefined
        elsif (TRIPORT) then
            wr_reg <= dp_ram(to_integer(wr_addr));
        else
            wr_reg <= (others => '0');  -- Disabled
        end if;
    end if;
end process;

-- Note: Read-enable logic is enabled only in test-mode, mostly to facilitate
--       compatibility with specific formal verification tools.
p_ram_out : process(rd_clk)
begin
    if rising_edge(rd_clk) then
        if (SIMTEST and rd_en = '0') then
            rd_reg <= (others => 'X');
        elsif (SIMTEST and wr_en = '1' and wr_addr = rd_addr) THEN
            rd_reg <= (OTHERS => 'X');
        else
            rd_reg <= dp_ram(to_integer(rd_addr));
        end if;
    end if;
end process;

end infer_dpram;

---------------------------------------------------------------------

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
library unisim;
use     unisim.vcomponents.all;

entity dpram is
    generic (
    AWIDTH  : positive;             -- Address width (bits)
    DWIDTH  : positive;             -- Data width (bits)
    SIMTEST : boolean := false;     -- Formal verification mode?
    TRIPORT : boolean := false);    -- Enable "wr_rval" port?
    port (
    wr_clk  : in  std_logic;
    wr_addr : in  unsigned(AWIDTH-1 downto 0);
    wr_en   : in  std_logic;
    wr_val  : in  std_logic_vector(DWIDTH-1 downto 0);
    wr_rval : out std_logic_vector(DWIDTH-1 downto 0);
    rd_clk  : in  std_logic;
    rd_addr : in  unsigned(AWIDTH-1 downto 0);
    rd_en   : in  std_logic := '1';
    rd_val  : out std_logic_vector(DWIDTH-1 downto 0));
end dpram;

architecture xilinx of dpram is

subtype word_t is std_logic_vector(DWIDTH-1 downto 0);
signal rd_raw, rd_reg, wr_raw, wr_reg : word_t := (others => '0');
signal wr_addr_pad  : unsigned(4 downto 0) := (others => '0');
signal rd_addr_pad  : unsigned(4 downto 0) := (others => '0');

begin

-- Address widths from 1-8 use SelectRAM primitives.
gen_selectram : if (AWIDTH < 9) generate
    gen_bits : for b in 0 to DWIDTH-1 generate
        -- Choose the appropriate primitive based on size.
        gen_w5 : if (AWIDTH < 6) generate
            -- Zero-pad address if needed.
            wr_addr_pad <= resize(wr_addr, 5);
            rd_addr_pad <= resize(rd_addr, 5);

            -- Smallest SelectRAM primitive.
            RAM32X1D_inst : RAM32X1D
                port map (
                DPO     => rd_raw(b),
                SPO     => wr_raw(b),
                A0      => wr_addr_pad(0),
                A1      => wr_addr_pad(1),
                A2      => wr_addr_pad(2),
                A3      => wr_addr_pad(3),
                A4      => wr_addr_pad(4),
                D       => wr_val(b),
                DPRA0   => rd_addr_pad(0),
                DPRA1   => rd_addr_pad(1),
                DPRA2   => rd_addr_pad(2),
                DPRA3   => rd_addr_pad(3),
                DPRA4   => rd_addr_pad(4),
                WCLK    => wr_clk,
                WE      => wr_en);
        end generate;

        gen_w6 : if (AWIDTH = 6) generate
            -- 64x1 SelectRAM primitive.
            RAM64X1D_inst : RAM64X1D
                port map(
                DPO     => rd_raw(b),
                SPO     => wr_raw(b),
                A0      => wr_addr(0),
                A1      => wr_addr(1),
                A2      => wr_addr(2),
                A3      => wr_addr(3),
                A4      => wr_addr(4),
                A5      => wr_addr(5),
                D       => wr_val(b),
                DPRA0   => rd_addr(0),
                DPRA1   => rd_addr(1),
                DPRA2   => rd_addr(2),
                DPRA3   => rd_addr(3),
                DPRA4   => rd_addr(4),
                DPRA5   => rd_addr(5),
                WCLK    => wr_clk,
                WE      => wr_en);
        end generate;

        gen_w7 : if (AWIDTH = 7) generate
            -- 128x1 SelectRAM primitive.
            RAM128X1D_inst : RAM128X1D
                port map (
                DPO     => rd_raw(b),
                SPO     => wr_raw(b),
                A       => std_logic_vector(wr_addr),
                D       => wr_val(b),
                DPRA    => std_logic_vector(rd_addr),
                WCLK    => wr_clk,
                WE      => wr_en);
        end generate;

        gen_w8 : if (AWIDTH = 8) generate
            -- This is the largest available SelectRAM primitive on the Ultrascale chips.
            RAM256X1D_inst : RAM256X1D
                port map (
                DPO     => rd_raw(b),
                SPO     => wr_raw(b),
                A       => std_logic_vector(wr_addr),
                D       => wr_val(b),
                DPRA    => std_logic_vector(rd_addr),
                WCLK    => wr_clk,
                WE      => wr_en);
        end generate;
    end generate;

    -- Register for buffering async reads.
    -- (Plus logic for simulation-only formal verification.)
    p_rbuff : process(rd_clk)
    begin
        if rising_edge(rd_clk) then
            if (SIMTEST and rd_en = '0') then
                rd_reg <= (others => 'X');  -- Undefined
            else
                rd_reg <= rd_raw;           -- Normal read
            end if;
        end if;
    end process;

    p_wbuff : process(wr_clk)
    begin
        if rising_edge(wr_clk) then
            if (SIMTEST and not TRIPORT) then
                wr_reg <= (others => '0');  -- Disabled
            elsif (SIMTEST and wr_en = '1') then
                wr_reg <= (others => 'X');  -- Undefined
            else
                wr_reg <= wr_raw;           -- Normal read
            end if;
        end if;
    end process;
end generate;

gen_big : if (AWIDTH > 8) generate
    -- Above this size, infer BRAM instead.
    u_bram : entity work.infer_dpram
        generic map(
        AWIDTH      => AWIDTH,
        DWIDTH      => DWIDTH,
        SIMTEST     => SIMTEST,
        TRIPORT     => TRIPORT)
        port map(
        wr_clk      => wr_clk,
        wr_addr     => wr_addr,
        wr_en       => wr_en,
        wr_val      => wr_val,
        wr_rval     => wr_reg,
        rd_clk      => rd_clk,
        rd_addr     => rd_addr,
        rd_en       => rd_en,
        rd_val      => rd_reg);
end generate;

-- Drive top-level output.
rd_val  <= rd_reg;
wr_rval <= wr_reg;

end xilinx;
