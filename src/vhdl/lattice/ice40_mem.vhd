--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Inferred and explicit memory structures for Lattice iCE40 FPGAs.
--
-- This file implements the components defined in "common_mem", using
-- explicit components and inference templates for Lattice iCE40 FPGAs.
--
-- NOTE: Designs should only include ONE such implementation!  If your
-- project includes "xilinx/7series_mem.vhd", don't also include similar
-- files from the "lattice" or "microsemi" folder.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_primitives.all;

-- Deferred constant definition(s):
package body common_primitives is
    -- 256x16 has 8 address bits. 
    -- TODO: 256x16 supports per-bit write enable, maybe should make a new generic module to take advantage of that
    -- Or could force 2048x2 in TCAM to only waste half of the memory?
    constant PREFER_DPRAM_AWIDTH : positive := 8;

    -- TODO: Add support for Vernier clock generator on this platform.
    function create_vernier_config(
        input_hz    : natural;
        sync_tau_ms : real := VERNIER_DEFAULT_TAU_MS;
        sync_aux_en : boolean := VERNIER_DEFAULT_AUX_EN)
    return vernier_config is begin
        return VERNIER_DISABLED;
    end function;
end package body;

---------------------------------------------------------------------

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;

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

architecture ice40 of dpram is


subtype word_t is std_logic_vector(DWIDTH-1 downto 0);
type dp_ram_t is array(0 to 2**AWIDTH-1) of word_t;
signal dp_ram     : dp_ram_t := (others => (others => '0'));
signal dp_ram_tri : dp_ram_t := (others => (others => '0'));

signal rd_reg, wr_reg : word_t := (others => '0');

signal i_wr_addr : integer range 0 to 2**AWIDTH-1;
signal i_rd_addr : integer range 0 to 2**AWIDTH-1;

begin

i_wr_addr <= to_integer(wr_addr);
i_rd_addr <= to_integer(rd_addr);


-- infer BRAM.
-- Yosys is not very good at inferring RAM. This syntax is known to work
process(wr_clk, rd_clk)
begin
    if rising_edge(wr_clk) then
        if (wr_en = '1') then
            dp_ram(i_wr_addr) <= wr_val;
        end if;
    end if;
      
    if rising_edge(rd_clk) then
        if (rd_en = '1') then
            rd_val <= dp_ram(i_rd_addr);
        end if;
    end if;
end process;


gen_triport : if (TRIPORT) generate
    -- generate a copy of the memory array that reads from the write address
    process(wr_clk)
    begin
        if rising_edge(wr_clk) then
            if (wr_en = '1') then
                dp_ram_tri(i_wr_addr) <= wr_val;
            end if;
            wr_rval <= dp_ram_tri(i_wr_addr);
        end if;
    end process;
end generate;

gen_twoport : if (not TRIPORT) generate
    wr_rval <= (others => '0');
end generate;


end ice40;
