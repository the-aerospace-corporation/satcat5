--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Inferred and explicit memory structures for Microsemi PolarFire FPGAs.
--
-- This file implements the components defined in "common_mem", using
-- explicit components and inference templates for Microsemi PolarFire FPGAs.
--
-- NOTE: Designs should only include ONE such implementation!  If your
-- project includes "xilinx/7series_mem.vhd", don't also include similar
-- files from the "lattice" or "microsemi" folder.
--
-- Reads and writes are both synchronous.  Read data is available on
-- the clock cycle after address is presented.
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

-- Deferred constant definition(s):
package body common_primitives is
    -- RAM64X12 supports 6-bit addresses.
    constant PREFER_DPRAM_AWIDTH : positive := 6;

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

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.common_functions.all;

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

architecture polarfire of dpram is

subtype word_t is std_logic_vector(DWIDTH-1 downto 0);
signal rd_reg, wr_reg : word_t := (others => '0');

function resize_slv(a: std_logic_vector; w: natural) return std_logic_vector is
begin
    return std_logic_vector(resize(UNSIGNED(a), w));
end;

-- small ram signals
--constant RAM12_COUNT : positive := (DWIDTH+11)/12;
constant RAM12_COUNT : integer := (DWIDTH+11)/12;
signal wr_addr_pad : std_logic_vector(5 downto 0) := (others => '0');
signal rd_addr_pad : std_logic_vector(5 downto 0) := (others => '0');
signal wr_val_pad  : std_logic_vector(12*RAM12_COUNT-1 downto 0) := (others => '0');
signal rd_val_pad  : std_logic_vector(12*RAM12_COUNT-1 downto 0) := (others => '0');

component RAM64x12
    port(
    W_EN            : in  std_logic;
    W_CLK           : in  std_logic;
    W_ADDR          : in  std_logic_vector(5 downto 0);
    W_DATA          : in  std_logic_vector(11 downto 0);
    BLK_EN          : in  std_logic;
    R_CLK           : in  std_logic;
    R_ADDR          : in  std_logic_vector(5 downto 0);
    R_ADDR_BYPASS   : in  std_logic; 
    R_ADDR_EN       : in  std_logic;
    R_ADDR_SL_N     : in  std_logic;
    R_ADDR_SD       : in  std_logic;
    R_ADDR_AL_N     : in  std_logic;
    R_ADDR_AD_N     : in  std_logic;
    R_DATA          : out std_logic_vector(11 downto 0);
    R_DATA_BYPASS   : in  std_logic;
    R_DATA_EN       : in  std_logic;
    R_DATA_SL_N     : in  std_logic;
    R_DATA_SD       : in  std_logic;
    R_DATA_AL_N     : in  std_logic;
    R_DATA_AD_N     : in  std_logic;
    BUSY_FB         : in  std_logic;
    ACCESS_BUSY     : out std_logic);
end component;


begin

-- Address widths from 1-6 use uSRAM primitives.
gen_usram : if (AWIDTH < 7) generate
    -- Zero-pad address if needed.
    wr_addr_pad <= std_logic_vector(resize(wr_addr, 6));
    rd_addr_pad <= std_logic_vector(resize(rd_addr, 6)); 
    -- Zero-pad data if needed to next highest multiple of 12 bits
    wr_val_pad <= resize_slv(wr_val, 12*RAM12_COUNT);
    rd_reg <= rd_val_pad(DWIDTH-1 downto 0);

    gen_bits : for b in 0 to RAM12_COUNT-1 generate
        -- See PolarFire_FPGA_Fabric_UG0680_V6 section 7.2.1 for configuration
        RAM64x12_inst : RAM64x12
            port map(
            W_EN =>             wr_en,
            W_CLK =>            wr_clk,
            W_ADDR =>           wr_addr_pad,
            W_DATA =>           wr_val_pad(12*(b+1)-1 downto 12*b),
            BLK_EN =>           '1',
            R_CLK =>            rd_clk,
            R_ADDR =>           rd_addr_pad,
            R_ADDR_BYPASS =>    '1', -- Bypass register on read address TODO: pin table does not match truth table?
            R_ADDR_EN =>        '0', -- don't care
            R_ADDR_SL_N =>      '1', -- Disable asynchronous load
            R_ADDR_SD =>        '0', -- don't care
            R_ADDR_AL_N =>      '1', -- Disable asynchronous load
            R_ADDR_AD_N =>      '0', -- don't care
            R_DATA =>           rd_val_pad(12*(b+1)-1 downto 12*b),
            R_DATA_BYPASS =>    '0', -- use register on read data
            R_DATA_EN =>        rd_en,
            R_DATA_SL_N =>      '1', -- Disable asynchronous load
            R_DATA_SD =>        '0', -- don't care
            R_DATA_AL_N =>      '1', -- Disable asynchronous load
            R_DATA_AD_N =>      '0', -- don't care
            BUSY_FB =>          '0',
            ACCESS_BUSY =>      open);
    end generate;

    gen_tri : if TRIPORT generate
        assert false report "TRIBUFF not implemented" severity error;
    end generate;
    wr_reg <= (others => '0');  -- Disabled
end generate;

gen_lsram : if (AWIDTH > 6) generate
    -- Above this size, infer LSRAM instead.
    u_lsram : entity work.infer_dpram
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


end polarfire;
