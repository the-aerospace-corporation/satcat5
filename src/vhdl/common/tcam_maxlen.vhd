--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Max-length prefix (MLP) helper module for the TCAM block
--
-- This module implements a pipelined priority encoder for efficient
-- maximum-length prefix matching in the multipurpose TCAM block.
-- Throughput is one bit-vector per clock, with a latency equal to
-- log2_ceil(TABLE_SIZE).  This block also tracks the prefix-length
-- of each table entry.
--
-- The algorithm is a pipelined single-elimination tournament.
-- In the input stage, each potential match presents its prefix length;
-- all others present zero.  Leaf-cells are compared two at a time in
-- a binary tree; the final root node is the "winner".
--
-- The error strobe is asserted if a tie occurs in any tournament stage.
--
-- An example with TABLE_SIZE = 4:
--  Layer:  L2     L1      L0
--  -------------------------------------------
--  Inputs  N3 -?- N1 --?- N0   Output node
--          N4 /       /        (Note indexing)
--          N5 -?- N2 /
--          N6 /
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.tcam_constants.all;

entity tcam_maxlen is
    generic (
    INPUT_WIDTH : positive;
    META_WIDTH  : natural;
    TABLE_SIZE  : positive);
    port (
    -- Mask to be priority-ranked.
    in_mask     : in  std_logic_vector(TABLE_SIZE-1 downto 0);
    in_type     : in  search_type;

    -- Final output selection.
    out_index   : out integer range 0 to TABLE_SIZE-1;
    out_found   : out std_logic;
    out_type    : out search_type;
    out_error   : out std_logic;

    -- Matched delay data and metadata.
    in_data     : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0);
    out_data    : out std_logic_vector(INPUT_WIDTH-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);

    -- Set priority for each table entry.
    cfg_clear   : in  std_logic;
    cfg_index   : in  integer range 0 to TABLE_SIZE-1;
    cfg_plen    : in  integer range 1 to INPUT_WIDTH;
    cfg_write   : in  std_logic;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end tcam_maxlen;

architecture tcam_maxlen of tcam_maxlen is

-- Calculate the flattened index for the given layer/index.
-- (i.e., The node indices in the tree diagram above.)
-- Note: Layer 0, Index 0 is the output node.
function tree_idx(layer, idx : integer) return integer is
begin
    assert (idx < 2**layer) report "Invalid index";
    return (2**layer - 1) + idx;
end function;

-- How many ranks required in this tournament?
-- Note: A binary tree with (2^N) leaves contains (2^N - 1) nodes.
constant TLAYERS    : positive := log2_ceil(TABLE_SIZE);
constant TSIZE      : positive := 2**TLAYERS - 1;

-- Convenience types for prefix-lengths. (0 = No match)
subtype plen_t is integer range 0 to INPUT_WIDTH;   -- Prefix length
subtype ridx_t is integer range 0 to TABLE_SIZE-1;  -- Table row-index
subtype data_t is std_logic_vector(INPUT_WIDTH-1 downto 0);
subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);
type plen_array is array(natural range <>) of plen_t;
type ridx_array is array(natural range <>) of ridx_t;
type data_array is array(natural range <>) of data_t;
type meta_array is array(natural range <>) of meta_t;
type type_array is array(natural range <>) of search_type;

-- Store the prefix-length for each table entry.
signal store_plen   : plen_array(TABLE_SIZE-1 downto 0) := (others => 0);

-- Pipelined tournament tree.
signal tree_plen    : plen_array(TSIZE-1 downto 0) := (others => 0);
signal tree_ridx    : ridx_array(TSIZE-1 downto 0) := (others => 0);
signal tree_error   : std_logic_vector(TSIZE-1 downto 0) := (others => '0');
signal dly_data     : data_array(TLAYERS-1 downto 0) := (others => (others => '0'));
signal dly_meta     : meta_array(TLAYERS-1 downto 0) := (others => (others => '0'));
signal dly_type     : type_array(TLAYERS-1 downto 0) := (others => TCAM_SEARCH_NONE);

begin

-- Final output is node zero of the tree.
out_index   <= tree_ridx(0);
out_found   <= bool2bit(tree_plen(0) > 0);
out_data    <= dly_data(0);
out_meta    <= dly_meta(0);
out_type    <= dly_type(0);
out_error   <= or_reduce(tree_error);

-- Store the prefix-length for each table entry.
p_ref : process(clk)
begin
    if rising_edge(clk) then
        for n in 0 to TABLE_SIZE-1 loop
            if (reset_p = '1' or cfg_clear = '1') then
                store_plen(n) <= 0;
            elsif (cfg_write = '1' and cfg_index = n) then
                store_plen(n) <= cfg_plen;
            end if;
        end loop;
    end if;
end process;

-- Pipelined tournament tree.
-- Note: Some tools require that a single process drives the entire array.
p_tree : process(clk)
    impure function get_plen(layer, idx : natural) return plen_t is
    begin
        if (layer < TLAYERS) then
            return tree_plen(tree_idx(layer, idx));     -- Pull from tree
        elsif (idx >= TABLE_SIZE) then
            return 0;                                   -- Zero-padding
        elsif (in_mask(idx) = '0') then
            return 0;                                   -- Non-matching input
        else
            return store_plen(idx);                     -- Matching input
        end if;
    end function;

    impure function get_ridx(layer, idx : natural) return ridx_t is
    begin
        if (layer < TLAYERS) then
            return tree_ridx(tree_idx(layer, idx));     -- Pull from tree
        elsif (idx < TABLE_SIZE) then
            return idx;                                 -- Input node
        else
            return 0;                                   -- Zero-padding
        end if;
    end function;

    impure function get_error(layer, idx : natural) return std_logic is
    begin
        if (layer < TLAYERS) then
            return tree_error(tree_idx(layer, idx));    -- Pull from tree
        else
            return '0';                                 -- First-tier input
        end if;
    end function;

    variable plen1, plen2 : plen_t;
    variable ridx1, ridx2 : ridx_t;
    variable err1,  err2  : std_logic;
begin
    if rising_edge(clk) then
        -- Instantiate each layer of the tournament tree.
        for layer in 0 to TLAYERS-1 loop
            for idx in 0 to 2**layer-1 loop
                -- Get the two competing inputs from previous layer.
                plen1 := get_plen(layer+1, 2*idx+0);
                plen2 := get_plen(layer+1, 2*idx+1);
                ridx1 := get_ridx(layer+1, 2*idx+0);
                ridx2 := get_ridx(layer+1, 2*idx+1);
                err1 := get_error(layer+1, 2*idx+0);
                err2 := get_error(layer+1, 2*idx+1);
                -- Compare prefix lengths and keep the winner.
                -- (Arbitrarily favor #1 in case of tie.)
                if (plen1 < plen2) then
                    tree_plen(tree_idx(layer, idx)) <= plen2;
                    tree_ridx(tree_idx(layer, idx)) <= ridx2;
                else
                    tree_plen(tree_idx(layer, idx)) <= plen1;
                    tree_ridx(tree_idx(layer, idx)) <= ridx1;
                end if;
                -- Check for collisions.
                tree_error(tree_idx(layer, idx)) <=
                    err1 or err2 or bool2bit(plen1 = plen2 and plen1 > 0);
            end loop;
        end loop;

        -- Matched delay for metadata and ready strobe.
        if (reset_p = '1') then
            dly_data    <= (others => (others => '0'));
            dly_meta    <= (others => (others => '0'));
            dly_type    <= (others => TCAM_SEARCH_NONE);
        else
            dly_data    <= in_data & dly_data(TLAYERS-1 downto 1);
            dly_meta    <= in_meta & dly_meta(TLAYERS-1 downto 1);
            dly_type    <= in_type & dly_type(TLAYERS-1 downto 1);
        end if;
    end if;
end process;

end tcam_maxlen;
