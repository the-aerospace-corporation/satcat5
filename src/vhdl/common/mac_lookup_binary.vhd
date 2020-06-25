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
-- MAC-address lookup by binary search, suitable for high-speed designs.
--
-- This module implements the same function as mac_address_simple, but uses
-- a more complex algorithm to provide considerably higher throughput.
-- This allows operation at high speed or with larger tables.  Search time
-- grows logarithmically with table size, though insertion remains linear.
-- As a result, search lookup must pause during that process, though it
-- should be quite rare during normal operation.
--
-- The design includes a scrubber that removes old entries and checks for
-- data integrity (table contents match and remain sorted).  The process
-- begins after "scrub_req" is strobed, typically about once a second.
--
-- Latency and throughput are calculated by the unit test.  For a table with
-- up to 31 addresses, worst-case latency is 14 clock cycles.  Every doubling
-- in size adds two additional clock cycles.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity mac_lookup_binary is
    generic (
    INPUT_WIDTH     : integer;          -- Width of main data port
    PORT_COUNT      : integer;          -- Number of Ethernet ports
    TABLE_SIZE      : integer := 255;   -- Max stored MAC addresses
    SCRUB_TIMEOUT   : integer := 15);   -- Timeout for stale entries
    port (
    -- Main input (Ethernet frame) uses AXI-stream flow control.
    -- PSRC is the input port-mask and must be held for the full frame.
    in_psrc         : in  std_logic_vector(PORT_COUNT-1 downto 0);
    in_data         : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
    in_last         : in  std_logic;
    in_valid        : in  std_logic;
    in_ready        : out std_logic;

    -- Search result is the port mask for the destination port(s).
    out_pdst        : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_valid       : out std_logic;
    out_ready       : in  std_logic;

    -- Scrub interface
    scrub_req       : in  std_logic;
    scrub_busy      : out std_logic;
    scrub_remove    : out std_logic;

    -- Error strobes
    error_full      : out std_logic;    -- No room for new address
    error_table     : out std_logic;    -- Table integrity check failed

    -- System interface
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_lookup_binary;

architecture mac_lookup_binary of mac_lookup_binary is

-- Define various convenience types.
constant TSCRUB_WIDTH : integer := log2_ceil(SCRUB_TIMEOUT + 1);
subtype mac_addr_t is unsigned(47 downto 0);
subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype table_idx_t is integer range 0 to TABLE_SIZE;
subtype scrub_count_t is unsigned(TSCRUB_WIDTH-1 downto 0);
subtype table_vec_t is std_logic_vector(47+PORT_COUNT+TSCRUB_WIDTH downto 0);

type table_row_t is record
    mac     : mac_addr_t;
    mask    : port_mask_t;
    tscrub  : scrub_count_t;
end record;
constant ROW_EMPTY : table_row_t := (
    mac => (others => '0'), mask => (others => '0'), tscrub => (others => '0'));

-- Convert from MAC/mask/counter to std_logic_vector and back.
function row2vec(row : table_row_t) return table_vec_t is
    variable temp : table_vec_t :=
        std_logic_vector(row.tscrub) &
        std_logic_vector(row.mask) &
        std_logic_vector(row.mac);
begin
    return temp;
end function;

function vec2row(vec : table_vec_t) return table_row_t is
    variable row : table_row_t := ROW_EMPTY;
begin
    row.tscrub  := unsigned(vec(47+PORT_COUNT+TSCRUB_WIDTH downto 48+PORT_COUNT));
    row.mask    := std_logic_vector(vec(47+PORT_COUNT downto 48));
    row.mac     := unsigned(vec(47 downto 0));
    return row;
end function;

-- Shift register extracts destination and source MAC address.
constant MAX_COUNT : integer := (95+INPUT_WIDTH) / INPUT_WIDTH;
signal in_ready_i   : std_logic := '0';
signal mac_wcount   : integer range 0 to MAX_COUNT := MAX_COUNT;
signal mac_dst      : mac_addr_t := (others => '0');
signal mac_src      : mac_addr_t := (others => '0');
signal mac_psrc     : port_mask_t := (others => '0');
signal mac_valid    : std_logic := '0';
signal mac_ready    : std_logic := '0';

-- Dual-port block-RAM (one read, one write)
signal read_addr    : table_idx_t := 0;
signal read_addr_a  : table_idx_t := 0;
signal read_addr_b  : table_idx_t := 0;
signal read_addr_c  : table_idx_t := 0;
signal read_addr_d  : table_idx_t := 0;
signal addr_eql_lo  : std_logic := '0';
signal addr_eql_hi  : std_logic := '0';
signal read_val     : table_row_t := ROW_EMPTY;
signal write_addr   : table_idx_t := 0;
signal write_val    : table_row_t := ROW_EMPTY;
signal write_en     : std_logic := '0';

-- Combinational logic for comparators.
signal read_lt_dst  : std_logic := '0';
signal read_eq_dst  : std_logic := '0';
signal read_lt_src  : std_logic := '0';
signal read_eq_src  : std_logic := '0';

-- Search and insertion state machine.
type search_state_t is (
    SEARCH_SCRUB,    -- Idle / scrub
    SEARCH_START,    -- Binary search (setup)
    SEARCH_FIND_DST, -- Binary search (destination)
    SEARCH_FIND_SRC, -- Binary search (source)
    SEARCH_INSERT,   -- New-address insertion
    SEARCH_REMOVE);  -- Old-address removal
signal row_count    : table_idx_t := 0;
signal scrub_busy_i : std_logic := '0';
signal scrub_rd_cnt : integer range 0 to 2;
signal search_state : search_state_t := SEARCH_SCRUB;
signal search_pdst  : port_mask_t := (others => '0');
signal out_pdst_i   : port_mask_t := (others => '0');

begin

-- Drive external copies of various internal signals.
in_ready    <= in_ready_i;
out_pdst    <= out_pdst_i;
scrub_busy  <= scrub_busy_i;

-- Upstream flow control: Halt input if next word would be end of MAC
--  address and we aren't ready to start a new search.  This ensures
--  a hard upper bound on latency.
in_ready_i <= bool2bit(search_state = SEARCH_SCRUB or mac_wcount /= 1);

-- Shift register extracts destination and source MAC address.
p_mac_sreg : process(clk)
    -- Input arrives N bits at a time, how many clocks until we have
    -- destination and source (96 bits total, may not divide evenly)
    variable sreg : std_logic_vector(MAX_COUNT*INPUT_WIDTH-1 downto 0) := (others => '0');
begin
    if rising_edge(clk) then
        -- Update shift register if applicable.
        -- Note: Ethernet is always MSW-first.
        if (in_valid = '1' and in_ready_i = '1') then
            sreg := sreg(sreg'left-INPUT_WIDTH downto 0) & in_data;
        end if;

        -- Latch outputs on the last cycle, so they are otherwise stable.
        -- (This gives us a few extra clock cycles for the search.)
        if (in_valid = '1' and in_ready_i = '1' and mac_wcount = 1) then
            assert (mac_valid = '0' or mac_ready = '1')
                report "Search not finished before next packet." severity warning;
            mac_psrc  <= in_psrc;
            mac_dst   <= unsigned(sreg(sreg'left downto sreg'left-47));
            mac_src   <= unsigned(sreg(sreg'left-48 downto sreg'left-95));
            mac_valid <= '1';
        elsif (mac_ready = '1') then
            mac_valid <= '0';
        end if;

        -- Update word-count state machine and upstream flow control.
        if (reset_p = '1') then
            mac_wcount <= MAX_COUNT;            -- Ready for first frame.
        elsif (in_valid = '1' and in_ready_i = '1') then
            -- Update counter (marks end of destination/source MAC).
            if (in_last = '1') then
                mac_wcount <= MAX_COUNT;        -- Get ready for next frame.
            elsif (mac_wcount > 0) then
                mac_wcount <= mac_wcount - 1;   -- Still reading MAC.
            end if;
        end if;
    end if;
end process;

-- Dual-port block-RAM (one port read-only, one port read/write)
-- Note: Read-before-write is required for insertion procedure.
-- Note: Final row is never used, but including it simplifies address masking logic.
p_table : process(clk)
    type table_array_t is array(0 to TABLE_SIZE) of table_vec_t;
    variable table_ram : table_array_t := (others => row2vec(ROW_EMPTY));
begin
    if rising_edge(clk) then
        read_val <= vec2row(table_ram(read_addr));
        if (write_en = '1') then
            table_ram(write_addr) := row2vec(write_val);
        end if;
    end if;
end process;

-- Combinational logic for comparators.
read_lt_dst <= bool2bit(read_val.mac < mac_dst);
read_eq_dst <= bool2bit(read_val.mac = mac_dst);
read_lt_src <= bool2bit(read_val.mac < mac_src);
read_eq_src <= bool2bit(read_val.mac = mac_src);

-- Search and update state machine performs multiple functions:
--  * Scrubbing
--      * Scrub-busy flag is set on request and cleared on completion.
--      * Scrubbing takes place while otherwise idle; it may be interrupted
--        at any time and resumes seamlessly.
--      * If an old entry (tscrub=0) is found, transition to removal mode.
--      * If an out-of-order entry is found, reset the entire table.
--      * Otherwise, simply decrement tscrub for each row of the table.
--  * Search
--      * Binary search for the index (or insertion point) of each MAC address.
--      * Each iteration takes two clock cycles but can be pipelined by
--        alternating between source and destination queries; unfortunately
--        the design is unlikely to close timing with a single-cycle loop.
--      * If the source address is found, refresh the scrub-countdown timer
--        for the associated table entry. (Single write, no separate state.)
--      * Otherwise, begin insertion of the new table entry. (Unless full.)
--  * Insertion
--      * Starting from the insertion point...
--      * Simultaneously write new table entry and read the existing entry.
--        Repeat this step for each subsequent row in the table, effectively
--        shifting each row down by one.
--      * Increment row count after finishing process.
--  * Removal
--      * Decrement row count before starting process.
--      * Starting from the deletion point, copy each row up by one.
--      * Continue until reaching the end of the table.
p_search : process(clk)
    constant BROADCAST_ADDR : mac_addr_t := (others => '1');
    variable dst_idx_lo, dst_idx_hi : table_idx_t := 0;
    variable src_idx_lo, src_idx_hi : table_idx_t := 0;
    variable dst_done, src_found, src_done, src_bcast : std_logic := '0';
    variable scrub_idx : table_idx_t := 0;
begin
    if rising_edge(clk) then
        -- Defaults for various strobes.
        error_full   <= '0';
        error_table  <= '0';
        mac_ready    <= '0';
        scrub_remove <= '0';
        write_en     <= '0';

        -- Pre-calculate all possible options for the next read address.
        -- Note: read_addr_d is a simple delay-by-one.
        if (search_state = SEARCH_FIND_DST) then
            read_addr_a <= (src_idx_hi + read_addr + 1) / 2;    -- Search / upper
            read_addr_b <= (src_idx_lo + read_addr - 1) / 2;    -- Search / lower
            addr_eql_hi <= bool2bit(read_addr = src_idx_hi);
            addr_eql_lo <= bool2bit(read_addr = src_idx_lo);
        else
            read_addr_a <= (dst_idx_hi + read_addr + 1) / 2;    -- Search / upper
            read_addr_b <= (dst_idx_lo + read_addr - 1) / 2;    -- Search / lower
            addr_eql_hi <= bool2bit(read_addr = dst_idx_hi);
            addr_eql_lo <= bool2bit(read_addr = dst_idx_lo);
        end if;
        if (read_addr < TABLE_SIZE) then
            read_addr_c <= read_addr + 1;   -- End / upper
        else
            read_addr_c <= 0;               -- (Wraparound)
        end if;
        read_addr_d <= read_addr;           -- End / lower (or simple delay)

        -- Update the scrub-busy flag.
        if (reset_p = '1') then
            scrub_busy_i <= '0';    -- Reset
        elsif ((scrub_req = '1') and (row_count > 0)) then
            scrub_busy_i <= '1';    -- Scrub request
        elsif (search_state = SEARCH_SCRUB and scrub_rd_cnt = 2 and scrub_idx+1 = row_count) then
            scrub_busy_i <= '0';    -- Scrub completed
        end if;

        -- Update the scrub-resume counter.
        if (scrub_busy_i = '0' or search_state /= SEARCH_SCRUB) then
            scrub_rd_cnt <= 0;  -- No scrub in progress.
        elsif (search_state = SEARCH_SCRUB and scrub_rd_cnt = 2 and scrub_idx+1 = row_count) then
            scrub_rd_cnt <= 0;  -- Scrub completed, revert to idle IMMEDIATELY.
        elsif (scrub_rd_cnt < 2) then
            scrub_rd_cnt <= scrub_rd_cnt + 1;
        end if;

        -- Update addresses and counters.
        if (search_state = SEARCH_SCRUB) then
            -- If any write takes place, it'll be to the current scrub index.
            write_val.mac    <= read_val.mac;
            write_val.mask   <= read_val.mask;
            write_val.tscrub <= read_val.tscrub - 1;
            write_en         <= bool2bit(scrub_rd_cnt = 2 and read_val.tscrub > 0);
            write_addr       <= scrub_idx;
            -- Drive the next read address:
            if (mac_valid = '1' and mac_ready = '0') then
                -- Start of new search.
                read_addr <= row_count / 2;
            elsif (scrub_idx + scrub_rd_cnt < TABLE_SIZE) then
                -- Start or resume scrubbing.
                read_addr <= scrub_idx + scrub_rd_cnt;
            end if;
            -- Reset overall search state.
            dst_done    := bool2bit(mac_dst = BROADCAST_ADDR);
            src_done    := bool2bit(mac_src = BROADCAST_ADDR);
            src_found   := bool2bit(mac_src = BROADCAST_ADDR);
            src_bcast   := bool2bit(mac_src = BROADCAST_ADDR);
            dst_idx_lo  := 0;
            src_idx_lo  := 0;
            if (row_count = 0) then
                dst_idx_hi  := 0;
                src_idx_hi  := 0;
            else
                dst_idx_hi  := row_count - 1;
                src_idx_hi  := row_count - 1;
            end if;
        elsif (search_state = SEARCH_START) then
            -- Reset output mask to broadcast mode (all but source).
            search_pdst <= not mac_psrc;
            -- Special case if table is empty: insert immediately.
            write_en         <= bool2bit(row_count = 0 and mac_src /= BROADCAST_ADDR);
            write_addr       <= 0;
            write_val.mac    <= mac_src;
            write_val.mask   <= mac_psrc;
            write_val.tscrub <= to_unsigned(SCRUB_TIMEOUT, TSCRUB_WIDTH);
            -- Get ready for first SRC read.
            read_addr <= row_count / 2;
        elsif (search_state = SEARCH_FIND_DST) then
            -- Now reading and comparing to destination MAC address.
            -- Note: Two-cycle read latency. Never write from this state.
            if (dst_done = '1') then            -- Done / no further action
                read_addr   <= read_addr_d;
            elsif (read_eq_dst = '1') then
                dst_done    := '1';             -- Exact match
                dst_idx_lo  := read_addr_d;
                dst_idx_hi  := read_addr_d;
                read_addr   <= read_addr_d;
                search_pdst <= read_val.mask;
            elsif (read_lt_dst = '0' and addr_eql_lo = '1') then
                dst_done    := '1';             -- End of search / lower
                dst_idx_lo  := read_addr_d;
                dst_idx_hi  := read_addr_d;
                read_addr   <= read_addr_d;
            elsif (read_lt_dst = '1' and addr_eql_hi = '1') then
                dst_done    := '1';             -- End of search / upper
                dst_idx_lo  := read_addr_d + 1;
                dst_idx_hi  := read_addr_d + 1;
                read_addr   <= read_addr_c;
            elsif (read_lt_dst = '0') then
                dst_idx_hi  := read_addr_d - 1; -- Continue / lower branch
                read_addr   <= read_addr_b;
            else
                dst_idx_lo  := read_addr_d + 1; -- Continue / upper branch
                read_addr   <= read_addr_a;
            end if;
        elsif (search_state = SEARCH_FIND_SRC) then
            -- Now reading and comparing to source MAC address.
            -- Note: Two-cycle read latency, conditional write (see below).
            if (src_done = '1') then            -- Done / no further action
                read_addr   <= read_addr_d;
            elsif (read_eq_src = '1') then
                src_found   := '1';             -- Exact match
                src_done    := '1';
                src_idx_lo  := read_addr_d;
                src_idx_hi  := read_addr_d;
                read_addr   <= read_addr_d;
            elsif (read_lt_src = '0' and addr_eql_lo = '1') then
                src_done    := '1';             -- End of search / lower
                src_idx_lo  := read_addr_d;
                src_idx_hi  := read_addr_d;
                read_addr   <= read_addr_d;
            elsif (read_lt_src = '1' and addr_eql_hi = '1') then
                src_done    := '1';             -- End of search / upper
                src_idx_lo  := read_addr_d + 1;
                src_idx_hi  := read_addr_d + 1;
                read_addr   <= read_addr_c;
            elsif (read_lt_src = '0') then
                src_idx_hi  := read_addr_d - 1; -- Continue / lower branch
                read_addr   <= read_addr_b;
            else
                src_idx_lo  := read_addr_d + 1; -- Continue / upper branch
                read_addr   <= read_addr_a;
            end if;
            -- Write only if we are about to finish search (update or insert).
            -- Note: This evicts older entry if the table is full.
            write_en         <= dst_done and src_done and not src_bcast;
            write_addr       <= src_idx_lo;
            write_val.mac    <= mac_src;
            write_val.mask   <= mac_psrc;
            write_val.tscrub <= to_unsigned(SCRUB_TIMEOUT, TSCRUB_WIDTH);
        elsif (search_state = SEARCH_INSERT) then
            -- Wait one cycle for read latency, then keep copying until end.
            if (read_addr < TABLE_SIZE) then
                read_addr <= read_addr + 1;
            end if;
            write_addr  <= read_addr;
            write_val   <= read_val;
            write_en    <= bool2bit(write_addr < row_count) and not mac_ready;
        elsif (search_state = SEARCH_REMOVE) then
            -- Just keep incrementing read address until end of table.
            -- (May read past valid data, but we'll just ignore it.)
            if (read_addr + 1 < TABLE_SIZE) then
                read_addr <= read_addr + 1;
            end if;
            -- Increment write address on all but the first cycle.
            if (scrub_rd_cnt = 0) then
                write_addr <= write_addr + 1;
            end if;
            -- Keep copying rows until end of table.
            write_en    <= '1';
            write_val   <= read_val;
        end if;

        -- Update overall state.
        if (reset_p = '1') then
            -- Global reset.
            search_state <= SEARCH_SCRUB;
            row_count    <= 0;
            scrub_idx    := 0;
        elsif (search_state = SEARCH_SCRUB) then
            -- Continue scrubbing while idle, interrupt as needed.
            if (mac_valid = '1' and mac_ready = '0') then
                -- Start of new search.
                search_state <= SEARCH_START;
            elsif (scrub_rd_cnt = 2 and read_val.tscrub = 0) then
                -- Found stale entry, begin removal.
                row_count    <= row_count - 1;
                scrub_remove <= '1';
                -- If there are more entries, move them as needed.
                if (scrub_idx+1 /= row_count) then
                    search_state <= SEARCH_REMOVE;
                end if;
            end if;
            -- Update the scrubbing index.
            if (scrub_busy_i = '0') then
                scrub_idx := 0;
            elsif (scrub_rd_cnt = 2) then
                if (scrub_idx+1 = row_count) then
                    scrub_idx := 0;
                elsif (read_val.tscrub > 0) then
                    scrub_idx := scrub_idx + 1;
                end if;
            end if;
        elsif (search_state = SEARCH_START) then
            -- Handle the empty case, otherwise proceed with normal search.
            if (row_count = 0) then
                search_state <= SEARCH_INSERT;
                mac_ready    <= '1';
            else
                search_state <= SEARCH_FIND_DST;
            end if;
        elsif (search_state = SEARCH_FIND_DST) then
            -- Ping-pong DST/SRC until finished.
            search_state <= SEARCH_FIND_SRC;
        elsif (search_state = SEARCH_FIND_SRC) then
            -- Ping-pong DST/SRC until finished.
            if ((src_done = '0') or (dst_done = '0')) then
                search_state <= SEARCH_FIND_DST;    -- Continue search
            elsif (src_found = '1') then
                search_state <= SEARCH_SCRUB;       -- Update entry
            elsif (row_count < TABLE_SIZE) then
                search_state <= SEARCH_INSERT;      -- Create new entry
            else
                search_state <= SEARCH_SCRUB;       -- Replace entry (full)
                error_full   <= '1';
                report "Table full, cannot insert." severity warning;
            end if;
            -- Consume MAC-address pair when finished.
            mac_ready <= src_done and dst_done;
        elsif (search_state = SEARCH_INSERT) then
            -- Keep copying until we reach end of table.
            if (write_addr = row_count) then
                search_state <= SEARCH_SCRUB;
                row_count    <= row_count + 1;
            end if;
        elsif (search_state = SEARCH_REMOVE) then
            -- Keep copying until we reach end of table.
            if (write_addr = row_count) then
                search_state <= SEARCH_SCRUB;
            end if;
        end if;
    end if;
end process;

-- One-word buffer for the final output mask.
p_out : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            out_valid <= '0';
        elsif (mac_ready = '1') then
            out_valid <= '1';
        elsif (out_ready = '1') then
            out_valid <= '0';
        end if;

        if (mac_ready = '1') then
            out_pdst_i <= search_pdst;
        end if;
    end if;
end process;

end mac_lookup_binary;
