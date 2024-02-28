--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- TCAM with integrated lookup-table.
--
-- The "TCAM-Core" block accepts an input, searches the TCAM table, and
-- returns the matching index, if one exists.  This block attaches a TCAM
-- to a lookup table, to fetch metadata associated with the search-result.
--
-- As with the TCAM core, various metadata is made available concurrently
-- with the search result.  Unlike the TCAM core, these outputs are also
-- made available one cycle *before* the primary output.  All are optional:
--  * Original search term (in_search / pre_search / out_search)
--  * User-specified metadata word (in_meta / pre_meta / out_meta)
--  * Result-ready strobe (pre_next / out_next)
--
-- Note: Due to feedback required from cfg_suggest to cfg_index in some
--       cache modes, we cannot integrate a write-queue into this wrapper.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.tcam_constants.all;

entity tcam_table is
    generic (
    IN_WIDTH    : positive;         -- Width of the search port
    META_WIDTH  : natural := 0;     -- Width of metadata port (optional)
    OUT_WIDTH   : positive;         -- Width of the result port
    TABLE_SIZE  : positive;         -- Max stored MAC addresses
    REPL_MODE   : repl_policy;      -- Replacement mode (see tcam_core)
    TCAM_MODE   : write_policy);    -- Enable wildcard searches?
    port (
    -- Search field for TCAM
    in_search   : in  std_logic_vector(IN_WIDTH-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_next     : in  std_logic;    -- Execute TCAM search

    -- Early copies of matched-delay metadata (Optional)
    pre_search  : out std_logic_vector(IN_WIDTH-1 downto 0);
    pre_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    pre_next    : out std_logic;

    -- Search result from lookup table
    out_search  : out std_logic_vector(IN_WIDTH-1 downto 0);
    out_result  : out std_logic_vector(OUT_WIDTH-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_found   : out std_logic;    -- Found a match?
    out_next    : out std_logic;    -- Next-result strobe
    out_error   : out std_logic;    -- TCAM internal error

    -- Write new table entries (AXI flow-control).
    cfg_clear   : in  std_logic := '0';
    cfg_suggest : out integer range 0 to TABLE_SIZE-1;
    cfg_index   : in  integer range 0 to TABLE_SIZE-1;
    cfg_plen    : in  integer range 1 to IN_WIDTH := IN_WIDTH;
    cfg_search  : in  std_logic_vector(IN_WIDTH-1 downto 0);
    cfg_result  : in  std_logic_vector(OUT_WIDTH-1 downto 0);
    cfg_valid   : in  std_logic;
    cfg_ready   : out std_logic;

    -- Scan interface is used to read table contents (optional).
    scan_index  : in  integer range 0 to TABLE_SIZE-1 := 0;
    scan_valid  : in  std_logic := '0';
    scan_ready  : out std_logic;
    scan_found  : out std_logic;
    scan_search : out std_logic_vector(IN_WIDTH-1 downto 0);
    scan_result : out std_logic_vector(OUT_WIDTH-1 downto 0);
    scan_mask   : out std_logic_vector(IN_WIDTH-1 downto 0);

    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end tcam_table;

architecture tcam_table of tcam_table is

-- Convert integer indices to unsigned.
constant TIDX_WIDTH : natural := log2_ceil(TABLE_SIZE);
subtype tbl_idx_t is integer range 0 to TABLE_SIZE-1;
subtype tbl_idx_u is unsigned(TIDX_WIDTH-1 downto 0);

-- TCAM search results
signal tcam_search  : std_logic_vector(IN_WIDTH-1 downto 0);
signal tcam_meta    : std_logic_vector(META_WIDTH-1 downto 0);
signal tcam_tidx    : tbl_idx_t;
signal tcam_tvec    : tbl_idx_u;
signal tcam_found   : std_logic;
signal tcam_next    : std_logic;

-- Other control signals
signal out_search_i : std_logic_vector(IN_WIDTH-1 downto 0) := (others => '0');
signal out_meta_i   : std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
signal out_found_i  : std_logic := '0';
signal out_next_i   : std_logic := '0';
signal cfg_ivec     : tbl_idx_u;
signal cfg_wren     : std_logic;
signal cfg_ready_i  : std_logic;
signal scan_tvec    : tbl_idx_u;

begin

-- Underlying TCAM block
u_tcam : entity work.tcam_core
    generic map(
    INPUT_WIDTH => IN_WIDTH,
    META_WIDTH  => META_WIDTH,
    TABLE_SIZE  => TABLE_SIZE,
    REPL_MODE   => REPL_MODE,
    TCAM_MODE   => TCAM_MODE)
    port map(
    in_data     => in_search,
    in_meta     => in_meta,
    in_next     => in_next,
    out_data    => tcam_search,
    out_meta    => tcam_meta,
    out_index   => tcam_tidx,
    out_found   => tcam_found,
    out_next    => tcam_next,
    out_error   => out_error,
    cfg_clear   => cfg_clear,
    cfg_suggest => cfg_suggest,
    cfg_index   => cfg_index,
    cfg_data    => cfg_search,
    cfg_valid   => cfg_valid,
    cfg_ready   => cfg_ready_i,
    scan_index  => scan_index,
    scan_valid  => scan_valid,
    scan_ready  => scan_ready,
    scan_found  => scan_found,
    scan_data   => scan_search,
    scan_mask   => scan_mask,
    clk         => clk,
    reset_p     => reset_p);

-- Lookup table is driven by the TCAM table-index, and updated in sync
-- with the TCAM contents for both new and existing/updated entries.
cfg_wren    <= cfg_valid and cfg_ready_i;
cfg_ivec    <= to_unsigned(cfg_index, TIDX_WIDTH);
tcam_tvec   <= to_unsigned(tcam_tidx, TIDX_WIDTH);
scan_tvec   <= to_unsigned(scan_index, TIDX_WIDTH);

u_lookup : dpram
    generic map(
    AWIDTH  => TIDX_WIDTH,
    DWIDTH  => OUT_WIDTH)
    port map(
    wr_clk  => clk,
    wr_addr => cfg_ivec,
    wr_en   => cfg_wren,
    wr_val  => cfg_result,
    rd_clk  => clk,
    rd_addr => tcam_tvec,
    rd_en   => tcam_next,
    rd_val  => out_result);

-- Second copy of the lookup table for "scan" port, if enabled.
-- (Mirrored writes ensure it has the same underlying data.)
u_lookup2 : dpram
    generic map(
    AWIDTH  => TIDX_WIDTH,
    DWIDTH  => OUT_WIDTH)
    port map(
    wr_clk  => clk,
    wr_addr => cfg_ivec,
    wr_en   => cfg_wren,
    wr_val  => cfg_result,
    rd_clk  => clk,
    rd_addr => scan_tvec,
    rd_en   => scan_valid,
    rd_val  => scan_result);

-- Matched delay for other fields.
p_dly : process(clk)
begin
    if rising_edge(clk) then
        out_search_i    <= tcam_search;
        out_meta_i      <= tcam_meta;
        out_found_i     <= tcam_found;
        out_next_i      <= tcam_next and not reset_p;
    end if;
end process;

-- Drive top-level outputs.
cfg_ready   <= cfg_ready_i;
pre_search  <= tcam_search;
pre_meta    <= tcam_meta;
pre_next    <= tcam_next;
out_search  <= out_search_i;
out_meta    <= out_meta_i;
out_found   <= out_found_i;
out_next    <= out_next_i;

end tcam_table;
