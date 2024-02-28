--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Byte-repacking FIFO
--
-- This block accepts a sparsely-packed stream using per-lane enable strobes,
-- and converts it to a densely-packed stream using the NLAST format.  (See
-- also: "fifo_packet.vhd").  By default, each lane is equal to one byte.
-- Input and output streams are always packed in "network" order, i.e.,
-- most-significant-lane first.
--
-- Other design rules:
--  * Input and output must be the same width.
--  * "End of frame" and "start of next frame" must occur on separate clocks.
--  * Last word must be non-empty (i.e., at least one lane-enable asserted).
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity fifo_repack is
    generic (
    LANE_COUNT  : positive;
    LANE_WIDTH  : positive := 8;
    META_WIDTH  : natural := 0);
    port (
    -- Input stream
    in_data     : in  std_logic_vector(LANE_WIDTH*LANE_COUNT-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_last     : in  std_logic := '0';
    in_write    : in  std_logic_vector(LANE_COUNT-1 downto 0);

    -- Output stream
    out_data    : out std_logic_vector(LANE_WIDTH*LANE_COUNT-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    out_nlast   : out integer range 0 to LANE_COUNT;
    out_last    : out std_logic;
    out_write   : out std_logic;

    -- System clock and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end fifo_repack;

architecture fifo_repack of fifo_repack is

-- How many stages in the sorting pipeline?
function sorting_stages(nlanes : positive) return natural is
begin
    if (nlanes = 1) then
        return 0;       -- No action required.
    elsif (nlanes = 2) then
        return 1;       -- Single swap unit
    else
        return nlanes;  -- Odd-even network (see below)
    end if;
end function;

subtype flag_array is std_logic_vector(0 to LANE_COUNT-1);
subtype lane_t is std_logic_vector(LANE_WIDTH-1 downto 0);
constant BZERO      : lane_t := (others => '0');
constant SORT_DEPTH : natural := sorting_stages(LANE_COUNT);
constant SREG_BYTES : positive := 2 * LANE_COUNT;
type lane_array is array(natural range<>) of lane_t;
type sort_array is array(0 to SORT_DEPTH) of lane_array(0 to LANE_COUNT-1);
type sort_flags is array(0 to SORT_DEPTH) of flag_array;

-- Find index of the Nth '1' bit, counting from MSB.
function find_sel_idx(x : std_logic_vector; n : natural) return natural is
    constant CMAX : positive := x'length - 1;
    variable cnt  : integer range 0 to CMAX := 0;
begin
    for b in 0 to CMAX loop
        if (x(x'left - b) = '1') then
            if (cnt = n) then
                return b;           -- Found index of interest
            else
                cnt := cnt + 1;     -- Count leading '1's
            end if;
        end if;
    end loop;
    return CMAX;                    -- No match found
end function;

-- Pre-pack input by sorting, one word at a time.
signal meta_write   : std_logic := '0';
signal sort_data    : sort_array := (others => (others => BZERO));
signal sort_last    : std_logic_vector(0 to SORT_DEPTH) := (others => '0');
signal sort_valid   : sort_flags := (others => (others => '0'));

-- Convert metadata from the sorting network.
signal pre_data     : lane_array(0 to LANE_COUNT-1) := (others => BZERO);
signal pre_lhot     : flag_array := (others => '0');
signal pre_last     : std_logic := '0';
signal pre_count    : integer range 0 to LANE_COUNT := 0;

-- Shift register accumulates packed subwords.
signal sreg_data    : lane_array(0 to SREG_BYTES-1) := (others => BZERO);
signal sreg_last    : std_logic_vector(0 to SREG_BYTES-1) := (others => '0');
signal sreg_lhot    : flag_array := (others => '0');
signal sreg_count   : integer range 0 to SREG_BYTES := 0;
signal sreg_next    : integer range 0 to LANE_COUNT := 0;

-- Final output conversion.
signal pack_data    : std_logic_vector(LANE_WIDTH*LANE_COUNT-1 downto 0) := (others => '0');
signal pack_nlast   : integer range 0 to LANE_COUNT := 0;
signal pack_last    : std_logic := '0';
signal pack_valid   : std_logic := '0';

begin

-- If per-packet metadata is enabled, it is handled by a separate FIFO.
-- (Required depth is given by the worst-case pipeline delay plus margin.)
gen_meta : if META_WIDTH > 0 generate
    meta_write <= in_last and or_reduce(in_write);

    u_meta : entity work.fifo_smol_sync
        generic map(
        IO_WIDTH    => META_WIDTH,
        DEPTH_LOG2  => log2_ceil(LANE_COUNT + 8))
        port map(
        in_data     => in_meta,
        in_write    => meta_write,
        out_data    => out_meta,
        out_valid   => open,
        out_read    => pack_last,
        clk         => clk,
        reset_p     => reset_p);
end generate;

-- Input buffering and format conversion:
-- All byte-array indexing is in chronological order, 0 = first/oldest.
p_input : process(clk)
begin
    if rising_edge(clk) then
        for n in 0 to LANE_COUNT-1 loop
            sort_data (0)(n) <= in_data(LANE_WIDTH*(LANE_COUNT-n)-1 downto LANE_WIDTH*(LANE_COUNT-1-n));
            sort_valid(0)(n) <= in_write(LANE_COUNT-1-n) and not reset_p;
        end loop;
        sort_last(0) <= or_reduce(in_write) and in_last;
    end if;
end process;

-- Pre-pack input, by sorting, one word at a time.
-- The index is the byte-valid strobe for each lane. See discussion here:
--  https://www.reddit.com/r/FPGA/comments/qe9j6s/vectorpacking_algorithm/
-- We need a stable sort, so we use the odd-even transpose sorting network:
--  https://www.inf.hs-flensburg.de/lang/algorithmen/sortieren/networks/oetsen.htm
gen_sort : for col in 0 to SORT_DEPTH-1 generate
    -- Instantiate logic for each column:
    p_col : process(clk)
    begin
        if rising_edge(clk) then
            -- Instantiate the sorting logic for this column...
            for row in 0 to LANE_COUNT-1 loop
                if (((row + col) mod 2) = 0) then
                    -- Upper half of a sorting pair.
                    if (row + 1 >= LANE_COUNT) then
                        -- Other half out-of-bounds -> passthrough.
                        sort_data (col+1)(row) <= sort_data (col)(row);
                        sort_valid(col+1)(row) <= sort_valid(col)(row) and not reset_p;
                    elsif (sort_valid(col)(row) = '1') then
                        -- Upper input is valid -> preserve order.
                        sort_data (col+1)(row) <= sort_data (col)(row);
                        sort_valid(col+1)(row) <= sort_valid(col)(row) and not reset_p;
                    else
                        -- Upper input is invalid --> Swap with the lower input.
                        sort_data (col+1)(row) <= sort_data (col)(row+1);
                        sort_valid(col+1)(row) <= sort_valid(col)(row+1) and not reset_p;
                    end if;
                else
                    -- Lower half of a sorting pair.
                    if (row = 0) then
                        -- Other half out-of-bounds -> passthrough.
                        sort_data (col+1)(row) <= sort_data (col)(row);
                        sort_valid(col+1)(row) <= sort_valid(col)(row) and not reset_p;
                    elsif (sort_valid(col)(row-1) = '1') then
                        -- Upper input is valid -> preserve order.
                        sort_data (col+1)(row) <= sort_data (col)(row);
                        sort_valid(col+1)(row) <= sort_valid(col)(row) and not reset_p;
                    else
                        -- Upper input is invalid -> Null output.
                        sort_data (col+1)(row) <= BZERO;
                        sort_valid(col+1)(row) <= '0';
                    end if;
                end if;
            end loop;
            -- Matched delay for the "last" strobe.
            sort_last(col+1) <= sort_last(col);
        end if;
    end process;
end generate;

-- Special case for the trivial single-byte case.
gen_pack0 : if SORT_DEPTH = 0 generate
    pack_data   <= sort_data(0)(0);
    pack_nlast  <= 1 when (sort_last(0) = '1') else 0;
    pack_last   <= sort_last(0);
    pack_valid  <= sort_valid(0)(0);
end generate;

-- Normal back-end: One-hot LAST strobes, shift-register, output conversion.
gen_pack1 : if SORT_DEPTH > 0 generate
    -- Convert metadata from the sorting network.
    pre_data <= sort_data(SORT_DEPTH);
    pre_last <= sort_last(SORT_DEPTH);

    -- Precalculate LAST and COUNT from next-to-last sorting stage.
    p_pre : process(clk)
        variable nvalid : integer range 0 to LANE_COUNT := 0;
    begin
        if rising_edge(clk) then
            nvalid := count_ones(sort_valid(SORT_DEPTH-1));

            for n in pre_lhot'range loop
                pre_lhot(n) <= sort_last(SORT_DEPTH-1) and bool2bit(n+1 = nvalid);
            end loop;

            if (reset_p = '1') then
                pre_count <= 0;
            else
                pre_count <= nvalid;
            end if;
        end if;
    end process;

    -- Shift register accumulates packed subwords.
    sreg_lhot <= sreg_last(0 to LANE_COUNT-1);
    sreg_next <= sreg_count when (sreg_count < LANE_COUNT)
            else sreg_count - LANE_COUNT;

    p_sreg : process(clk)
    begin
        if rising_edge(clk) then
            -- Determine the new state for each byte lane...
            for n in sreg_data'range loop
                if (n < sreg_next and sreg_count < LANE_COUNT) then
                    -- Keep current value
                    sreg_data(n) <= sreg_data(n);
                    sreg_last(n) <= sreg_last(n);
                elsif (n < sreg_next) then
                    -- Shift by LANE_COUNT.
                    sreg_data(n) <= sreg_data(n + LANE_COUNT);
                    sreg_last(n) <= sreg_last(n + LANE_COUNT);
                elsif (n - sreg_next < LANE_COUNT) then
                    -- Store next packed input.
                    sreg_data(n) <= pre_data(n - sreg_next);
                    sreg_last(n) <= pre_lhot(n - sreg_next);
                else
                    -- Past end of input -> Don't care.
                    sreg_data(n) <= BZERO;
                    sreg_last(n) <= '0';
                end if;
            end loop;

            -- Count bytes stored in SREG.
            if (reset_p = '1') then
                -- FIFO reset
                sreg_count <= 0;
            elsif (pre_last = '0') then
                -- Normal storage of full or partial words.
                sreg_count <= sreg_next + pre_count;
            elsif (sreg_next + pre_count <= LANE_COUNT) then
                -- Last word is padded to the first word boundary.
                sreg_count <= LANE_COUNT;
            else
                -- Last word is padded to the second word boundary.
                sreg_count <= 2*LANE_COUNT;
            end if;
        end if;
    end process;

    -- Final output conversion.
    p_pack : process(clk)
    begin
        if rising_edge(clk) then
            -- Copy output from shift-register, MSB-first.
            for n in pre_data'range loop
                pack_data(LANE_WIDTH*(LANE_COUNT-n)-1 downto LANE_WIDTH*(LANE_COUNT-1-n)) <= sreg_data(n);
            end loop;

            if (reset_p = '1' or sreg_count < LANE_COUNT) then
                -- No output this cycle.
                pack_valid  <= '0'; -- No output this cycle
                pack_last   <= '0';
                pack_nlast  <= 0;
            elsif (or_reduce(sreg_lhot) = '0') then
                pack_valid  <= '1'; -- Normal output
                pack_last   <= '0';
                pack_nlast  <= 0;
            else
                pack_valid  <= '1'; -- Last word in frame
                pack_last   <= '1';
                pack_nlast  <= 1 + to_integer(one_hot_decode(sreg_lhot, log2_ceil(LANE_COUNT)));
            end if;
        end if;
    end process;
end generate;

out_data    <= pack_data;
out_nlast   <= pack_nlast;
out_last    <= pack_last;
out_write   <= pack_valid;

end fifo_repack;
