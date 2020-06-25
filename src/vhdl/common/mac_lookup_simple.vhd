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
-- Simple variant of MAC-address lookup, suitable for low-speed designs.
--
-- This module implements a ultra-lightweight, resource-optimized MAC lookup
-- table. Given a candidate address, it simply iterates through the complete
-- list and returns the first match, if any.  Search time is equal to the
-- maximum number of addresses, so this approach is only suitable for low-
-- speed designs with a limited number of ports.
--
-- The design includes a scrubber that removes old entries, using a small
-- countdown timer stored alongside each table entry.  The process begins
-- after "scrub_req" is strobed, typically about once a second.
--
-- Worst-case latency/throughput of this design is proportional to table
-- size.  As a result, it is recommended for 8-bit datapaths only.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity mac_lookup_simple is
    generic (
    INPUT_WIDTH     : integer;          -- Width of main data port
    PORT_COUNT      : integer;          -- Number of Ethernet ports
    TABLE_SIZE      : integer := 31;    -- Max stored MAC addresses
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

    -- System interface
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_lookup_simple;

architecture mac_lookup_simple of mac_lookup_simple is

-- Define various convenience types.
constant TSCRUB_WIDTH : integer := log2_ceil(SCRUB_TIMEOUT+1);
subtype mac_addr_t is unsigned(47 downto 0);
subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype table_idx_t is integer range 0 to TABLE_SIZE-1;
subtype table_cnt_t is integer range 0 to TABLE_SIZE;
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
    -- Vivado's sim is not okay directly returning the joined vector
    -- so use a temp variable.
    variable ret_vec: std_logic_vector(TSCRUB_WIDTH+PORT_COUNT+48-1 downto 0);
begin
    ret_vec := std_logic_vector(row.tscrub)
            & std_logic_vector(row.mask)
            & std_logic_vector(row.mac);
    return ret_vec;
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
signal in_ready_i   : std_logic := '0';
signal mac_dst      : mac_addr_t := (others => '0');
signal mac_src      : mac_addr_t := (others => '0');
signal mac_rdy      : std_logic := '0';

-- Counter tracks number of active rows.
signal row_count    : table_cnt_t := 0;
signal row_insert   : std_logic := '0';
signal row_delete   : std_logic := '0';

-- Search & insertion state machine.
type search_state_t is (
    SEARCH_IDLE,    -- Idle / done
    SEARCH_START,   -- Start of new search
    SEARCH_RUN,     -- Iterating through table
    SEARCH_FINAL);  -- Reading final table entry
signal search_state : search_state_t := SEARCH_IDLE;
signal search_done  : std_logic := '0';
signal search_dst   : port_mask_t := (others => '0');
signal search_addr  : table_idx_t := 0;
signal search_rdval : table_row_t := ROW_EMPTY;
signal search_wrval : table_row_t := ROW_EMPTY;
signal search_wren  : std_logic := '0';
signal out_pending  : std_logic := '0';

-- Scrubbing state machine.
type scrub_state_t is (
    SCRUB_IDLE,     -- Idle / done
    SCRUB_READ,     -- Read next table row
    SCRUB_CHECK,    -- Check row status and update pointers
    SCRUB_WRITE,    -- Copy selected row to new location
    SCRUB_TRIM);    -- After scan, reduce table size
signal scrub_state  : scrub_state_t := SCRUB_IDLE;
signal scrub_addr   : table_idx_t := 0;
signal scrub_rdval  : table_row_t := ROW_EMPTY;
signal scrub_wrval  : table_row_t := ROW_EMPTY;
signal scrub_wren   : std_logic := '0';

begin

-- Drive external copies of various internal signals.
in_ready     <= in_ready_i;
out_pdst     <= search_dst;
out_valid    <= search_done or out_pending;
scrub_remove <= row_delete;

-- The main MAC address table.
-- (Inferred dual-port block-RAM, each port read/write capable.
p_table : process(clk)
    type table_array_t is array(0 to TABLE_SIZE-1) of table_vec_t;
    variable table_ram : table_array_t := (others => row2vec(ROW_EMPTY));
begin
    if rising_edge(clk) then
        search_rdval <= vec2row(table_ram(search_addr));
        scrub_rdval  <= vec2row(table_ram(scrub_addr));
        if (search_done = '1' and search_wren = '1') then
            table_ram(search_addr) := row2vec(search_wrval);
        end if;
        if (scrub_wren = '1') then
            table_ram(scrub_addr) := row2vec(scrub_wrval);
        end if;
    end if;
end process;

-- Shift register extracts destination and source MAC address.
p_mac_sreg : process(clk)
    -- Input arrives N bits at a time, how many clocks until we have
    -- destination and source (96 bits total, may not divide evenly)
    constant MAX_COUNT : integer := (95+INPUT_WIDTH) / INPUT_WIDTH;
    variable sreg   : std_logic_vector(MAX_COUNT*INPUT_WIDTH-1 downto 0) := (others => '0');
    variable count  : integer range 0 to MAX_COUNT;
begin
    if rising_edge(clk) then
        -- Update shift register if applicable.
        -- Note: Ethernet is always MSW-first.
        if (in_valid = '1' and in_ready_i = '1' and count > 0) then
            sreg := sreg(sreg'left-INPUT_WIDTH downto 0) & in_data;
            mac_rdy <= bool2bit(count = 1); -- Last MAC word, start search
        else
            mac_rdy <= '0';
        end if;
        mac_dst <= unsigned(sreg(sreg'left downto sreg'left-47));
        mac_src <= unsigned(sreg(sreg'left-48 downto sreg'left-95));

        -- While search is busy, continue accepting current packet but
        -- disallow future data.
        if (reset_p = '1') then
            in_ready_i <= '0';
        elsif (search_state = SEARCH_IDLE) then
            in_ready_i <= '1';
        elsif (in_valid = '1' and in_last = '1') then
            in_ready_i <= '0';
        else
            in_ready_i <= bool2bit(count = 0);
        end if;

        -- Update word-count state machine and ready strobe.
        if (reset_p = '1') then
            count := MAX_COUNT;     -- Ready for first frame.
        elsif (in_valid = '1' and in_ready_i = '1') then
            if (in_last = '1') then
                count := MAX_COUNT; -- Get ready for next frame.
            elsif (count > 0) then
                count := count - 1; -- Still reading MAC.
            end if;
        end if;
    end if;
end process;

-- Counter tracks number of active rows.
p_count : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            row_count <= 0;
        elsif (row_insert = '1' and row_delete = '0') then
            row_count <= row_count + 1;
            assert (row_count < TABLE_SIZE)
                report "Insert strobe while full." severity error;
        elsif (row_insert = '0' and row_delete = '1') then
            row_count <= row_count - 1;
            assert (row_count > 0)
                report "Delete strobe while empty." severity error;
        end if;
    end if;
end process;

-- Search & insertion state machine.
-- For each new search:
--  * Reset "found source" flag (unless broadcast)
--  * Reset "found destination" flag (unless broadcast)
--  * Default output port mask is broadcast (all but source)
--  * Iterate through addresses until end of table...
--      If a matching source is found, note the row index.
--      If a matching destination is found, change output port mask.
--  * Once we've reached the end...
--      If a matching source was found, update the table entry.
--      Otherwise, create a new table entry unless full.
p_search : process(clk)
    constant BROADCAST : mac_addr_t := (others => '1');
    variable found_src : std_logic := '0';
    variable found_idx : table_idx_t := 0;
begin
    if rising_edge(clk) then
        -- Set defaults (may be overridden below).
        search_done <= '0';
        row_insert  <= '0';
        error_full  <= '0';

        -- Input sanity check.
        assert (search_state = SEARCH_IDLE or mac_rdy = '0')
            report "Unexpected mac_rdy strobe" severity error;

        -- Update the source/destination matching flags.
        if (mac_rdy = '1') then
            -- New search, check for broadcast addresses.
            search_dst  <= not in_psrc;
            search_wren <= not bool2bit(mac_src = BROADCAST);
            found_src   := '0';
            found_idx   := 0;
        elsif (search_state /= SEARCH_IDLE and search_state /= SEARCH_START) then
            -- During readout, look for specific matches (note two-cycle lag).
            if (mac_dst = search_rdval.mac) then
                search_dst <= search_rdval.mask;
            end if;
            if (mac_src = search_rdval.mac) then
                found_src := '1';
            elsif (found_src = '0') then
                -- Keep updating address until found (note one-cycle lag).
                found_idx := search_addr;
            end if;
        end if;

        -- Address state machine.
        if (search_state = SEARCH_IDLE) then
            search_addr <= 0;               -- Ready for next search
            row_insert  <= mac_rdy and bool2bit(row_count = 0);
        elsif (search_state = SEARCH_FINAL and search_wren = '1') then
            -- End of search, update table appropriately:
            if (found_src = '1') then
                search_addr <= found_idx;   -- Update
            elsif (row_count < TABLE_SIZE) then
                search_addr <= row_count;   -- Append
                row_insert  <= '1';
            else
                report "Table full, cannot insert." severity warning;
                error_full  <= '1';         -- Error
            end if;
        elsif (search_addr+1 /= row_count) then
            search_addr <= search_addr + 1; -- Search / increment
        end if;

        -- Overall state machine.
        if (reset_p = '1') then
            -- System reset.
            search_state <= SEARCH_IDLE;
        elsif (mac_rdy = '1' and row_count = 0) then
            -- Empty table, end search immediately.
            search_state <= SEARCH_IDLE;
            search_done  <= '1';
        elsif (mac_rdy = '1' and row_count > 0) then
            -- Start of new search.
            search_state <= SEARCH_START;
        elsif (search_state = SEARCH_START and search_addr+1 = row_count) then
            -- Only one item to search.
            search_state <= SEARCH_FINAL;
        elsif (search_state = SEARCH_START) then
            -- Normal search.
            search_state <= SEARCH_RUN;
        elsif (search_state = SEARCH_RUN and search_addr+1 = row_count) then
            -- About to finish search.
            search_state <= SEARCH_FINAL;
        elsif (search_state = SEARCH_FINAL) then
            -- Search completed.
            search_state <= SEARCH_IDLE;
            search_done  <= '1';
        end if;

        -- Drive the out-pending flag.
        if (reset_p = '1' or out_ready = '1') then
            out_pending <= '0';
        elsif (search_done = '1') then
            out_pending <= '1';
        end if;
    end if;
end process;

search_wrval.mask   <= in_psrc;
search_wrval.mac    <= mac_src;
search_wrval.tscrub <= to_unsigned(SCRUB_TIMEOUT, TSCRUB_WIDTH);

-- Scrubbing state machine:
--  * Read through each entry in the table:
--      * If scrub countdown is zero, delete entry
--        (Increment read pointer only)
--      * Otherwise, copy the entry to the insertion point but decrement counter
--        (Increment read and write pointers)
--  * When done, strobe "row_delete" for each deleted entry.
--    (Increment write pointer until equal to read pointer)
-- Since we only copy entries, we are OK to run this concurrently with the
-- main search except for the final size update (each row_delete strobe).
p_scrub : process(clk)
    variable rd_ptr, wr_ptr : table_cnt_t := 0;
begin
    if rising_edge(clk) then
        row_delete <= '0';
        scrub_wren <= '0';
        scrub_busy <= bool2bit(scrub_state /= SCRUB_IDLE);
        if (reset_p = '1' or scrub_state = SCRUB_IDLE) then
            -- Idle/done, start new scrub on request.
            scrub_addr  <= 0;
            rd_ptr      := 0;
            wr_ptr      := 0;
            if (scrub_req = '1' and row_count > 0) then
                scrub_state <= SCRUB_READ;
            else
                scrub_state <= SCRUB_IDLE;
            end if;
        elsif (scrub_state = SCRUB_READ) then
            -- Increment read pointer while we wait (two cycle latency).
            scrub_state <= SCRUB_CHECK;
            rd_ptr      := rd_ptr + 1;
        elsif (scrub_state = SCRUB_CHECK) then
            -- Check row status and update pointers.
            if (scrub_rdval.tscrub /= 0) then
                -- Copy row to the new location and decrement countdown.
                scrub_state <= SCRUB_WRITE;
                scrub_addr  <= wr_ptr;
                scrub_wren  <= '1';
            elsif (rd_ptr /= row_count) then
                -- Purge current row and read the next one.
                scrub_state <= SCRUB_READ;
                scrub_addr  <= rd_ptr;
            else
                -- Purge current row and finish scan.
                scrub_state <= SCRUB_TRIM;
            end if;
        elsif (scrub_state = SCRUB_WRITE) then
            -- Write completed, increment pointer.
            wr_ptr := wr_ptr + 1;
            -- Done with scan?
            if (rd_ptr /= row_count) then
                scrub_state <= SCRUB_READ;
                scrub_addr  <= rd_ptr;
            else
                scrub_state <= SCRUB_TRIM;
            end if;
        elsif (scrub_state = SCRUB_TRIM) then
            -- After scan, reduce table size.
            if (rd_ptr = wr_ptr) then
                -- Trim completed, revert to idle.
                scrub_state <= SCRUB_IDLE;
            elsif (search_state = SEARCH_IDLE and mac_rdy = '0') then
                -- Adjust table size only while search is idle.
                row_delete  <= '1';
                wr_ptr      := wr_ptr + 1;
            end if;
        end if;
    end if;
end process;

-- Loopback for routine scrubbing updates.
scrub_wrval.mask    <= scrub_rdval.mask;
scrub_wrval.mac     <= scrub_rdval.mac;
scrub_wrval.tscrub  <= scrub_rdval.tscrub - 1;

end mac_lookup_simple;
