--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Pseudo-"Least-Recently-Used" (PLRU) cache controller for the TCAM block
--
-- This block monitors access to a CAM/TCAM cache, and indicates which
-- block should be evicted/overwritten using the "Tree-PLRU" algorithm.
-- This algorithm approximates the "Least-recently-used" criteria but
-- uses substantially fewer resources.
--
-- https://en.wikipedia.org/wiki/Pseudo-LRU
--
-- Minimum latency is four clock cycles. If TABLE_SIZE is not a power
-- of two, a few more cycles may sometimes be required for the recycling
-- algorithm that is used to constrain the output without bias.
-- (Note: Recycling is only possible if duty-cycle is less than 100%.
--        It's also slightly biased, but far better than nothing.)
-- TODO: Figure out a less biased alternative algorithm.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity tcam_cache_plru is
    generic (
    TABLE_SIZE  : positive);
    port (
    -- Update queue state for each successful search.
    in_index    : in  integer range 0 to TABLE_SIZE-1;
    in_read     : in  std_logic;
    in_write    : in  std_logic;

    -- Best candidate for eviction.
    out_index   : out integer range 0 to TABLE_SIZE-1;
    out_hold    : in  std_logic := '0';

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end tcam_cache_plru;

architecture tcam_cache_plru of tcam_cache_plru is

-- How many layers required in our tree?
-- Note: A binary tree with (2^N) leaves contains (2^N - 1) nodes.
constant TLAYERS    : positive := log2_ceil(TABLE_SIZE);
constant TSIZE      : positive := 2**TLAYERS - 1;
subtype index_word is unsigned(TLAYERS-1 downto 0);
subtype index_mask is std_logic_vector(TSIZE downto 0);

-- Calculate the flattened index for the given layer/index.
function tree_idx(layer, idx : natural) return natural is
begin
    assert (idx < 2**layer) report "Invalid index";
    return (2**layer - 1) + idx;
end function;

-- Given a layer and index word, find the corresponding tree-index.
-- (Top of tree is MSB, and so on down to leaf cells.)
function subidx(layer:natural; x:index_word) return natural is
    -- Truncate all but layer# MSBs.
    variable x2 : index_word := shift_right(x, TLAYERS-layer);
begin
    -- Tree-index for the Nth node in requested layer.
    return tree_idx(layer, to_integer(x2));
end function;

-- Given a tree state-vector, calculate the one-hot-vector
-- for each possible implied index (including zero-pad).
function tree_out(x : std_logic_vector) return index_mask is
    variable idx : index_word;
    variable hot : std_logic_vector(TSIZE downto 0) := (others => '1');
begin
    -- AND_REDUCE each path as we walk up the tree.
    for n in hot'range loop
        idx := to_unsigned(n, TLAYERS);
        for layer in idx'range loop
            if (x(subidx(layer, idx)) /= idx(idx'left-layer)) then
                hot(n) := '0';
            end if;
        end loop;
    end loop;
    return hot;
end function;

-- Input buffer / recycler state machine.
signal wr_index : index_word := (others => '0');
signal wr_rdy   : std_logic := '0';

-- State machine for each bit in the tree.
signal tree     : std_logic_vector(TSIZE-1 downto 0) := (others => '0');

-- Output conversion pipeline.
signal onehot   : index_mask := (others => '0');
signal rawidx   : index_word := (others => '0');
signal bufidx   : integer range 0 to TABLE_SIZE-1 := 0;

begin

-- Input buffer / recycler state machine.
p_in : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            wr_index <= (others => '0');
            wr_rdy   <= '0';
        elsif (in_write = '1' or in_read = '1') then
            wr_index <= to_unsigned(in_index, TLAYERS);
            wr_rdy   <= '1';
        else
            wr_index <= rawidx;
            wr_rdy   <= bool2bit(rawidx >= TABLE_SIZE);
        end if;
    end if;
end process;

-- State machine for each bit in the tree.
p_tree : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            tree <= (others => '0');
        elsif (wr_rdy = '1') then
            for layer in 0 to TLAYERS-1 loop
                tree(subidx(layer, wr_index)) <= not wr_index(wr_index'left-layer);
            end loop;
        end if;
    end if;
end process;

-- Output conversion pipeline.
p_out : process(clk)
    variable wr_count : integer range 0 to TABLE_SIZE := 0;
begin
    if rising_edge(clk) then
        -- Output buffer and mode selection:
        if (reset_p = '1') then
            bufidx <= 0;                    -- Global reset
        elsif (out_hold = '1') then
            bufidx <= bufidx;               -- Output freeze
        elsif (wr_count /= TABLE_SIZE) then
            -- Simple counter until full; PLRU may overwrite needlessly.
            bufidx <= wr_count;             -- Next empty slot
        elsif (rawidx < TABLE_SIZE) then
            -- PLRU output is [0..2^N), ignore anything out-of-bounds.
            bufidx <= to_integer(rawidx);   -- Next PLRU
        end if;

        -- Convert one-hot vector to an integer index.
        assert (one_hot_error(onehot) = '0')
            report "One-hot decode error" severity error;
        rawidx <= one_hot_decode(onehot, TLAYERS);

        -- Convert tree-state to a one-hot vector.
        onehot <= tree_out(tree);

        -- Update next-empty-slot counter.
        if (reset_p = '1') then
            wr_count := 0;
        elsif (in_write = '1' and wr_count /= TABLE_SIZE) then
            wr_count := wr_count + 1;
        end if;
    end if;
end process;

out_index <= bufidx;

end tcam_cache_plru;
