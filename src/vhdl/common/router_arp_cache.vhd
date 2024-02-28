--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Address Resolution Cache
--
-- This block queries and updates a table mapping 32-bit IPv4 addresses to
-- 48-bit MAC addresses, and signals a request for new information after
-- each cache miss.
--
-- All addresses are provided sequentially, one byte at a time in big-endian
-- order.  The first byte of an address is concurrent with the "first" strobe,
-- with remaining bytes provided on consecutive clock cycles.  Queries provide
-- the IPv4 address and reply with the MAC address; updates provide the IPv4
-- address followed by the MAC address.  All input pipes use AXI valid/ready
-- flow-control, but with a "first" strobe instead of a "last" strobe.  All
-- outputs use "write" strobes; supply your own FIFO if required.
--
-- Search uses a sequential variant of the scalable CAM described by:
--      Jiang, Weirong. "Scalable ternary content addressable memory
--      implementation using FPGAs." Architectures for Networking and
--      Communications Systems. IEEE, 2013.
--
-- Required BRAM size scales with the cache size.  If possible, the cache
-- should be large enough for the entire local subnet; overflows overwrite
-- the oldest entry.  For a cache with N entries, the sizes are as follows:
--   * CAM table (1024 rows of N-bit words) = One write, two read ports
--   * Address table (16N rows of 8-bit words) = One write, one read port
--
-- TODO: Detection or mitigation for ARP spoofing?
-- TODO: Implement LRU table replacement?  Flush entries after a timeout?
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity router_arp_cache is
    generic (
    TABLE_SIZE      : positive := 32);
    port (
    -- Query: Submit an IP address for search.
    query_first     : in  std_logic;    -- First-byte strobe
    query_addr      : in  byte_t;       -- IPv4 address
    query_valid     : in  std_logic;
    query_ready     : out std_logic;

    -- Reply: Respond to each Query with MAC address, if found.
    reply_first     : out std_logic;    -- First-byte strobe
    reply_match     : out std_logic;    -- Entry in table?
    reply_addr      : out byte_t;       -- MAC address
    reply_write     : out std_logic;

    -- Request: Request missing IP/MAC if any Query is not found.
    request_first   : out std_logic;    -- First-byte strobe
    request_addr    : out byte_t;       -- IPv4 address
    request_write   : out std_logic;

    -- Update: Write IP/MAC pairs to the cache.
    update_first    : in  std_logic;    -- First-byte strobe
    update_addr     : in  byte_t;       -- IPv4 then MAC
    update_valid    : in  std_logic;
    update_ready    : out std_logic;

    -- System clock and reset.
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end router_arp_cache;

architecture router_arp_cache of router_arp_cache is

-- Each metadata table entry is allocated 10 consecutive bytes.
-- Zero-padding this to 16 bytes per entry simplifies address calculations.
constant TABLE_META_REQ     : integer := 10;    -- Requested minimum size
constant TABLE_META_SHIFT   : integer := log2_ceil(TABLE_META_REQ);
constant TABLE_META_BYTES   : integer := 2**TABLE_META_SHIFT;
constant META_OFFSET_IP     : integer := 0;     -- Bytes 0-3 = IP address
constant META_OFFSET_MAC    : integer := 4;     -- Bytes 4-9 = MAC address

-- Calculate the size of address word required for metadata table.
constant TABLE_IDX_WIDTH : integer := log2_ceil(TABLE_SIZE) + TABLE_META_SHIFT;

-- IP-address CAM is a series of four 8-bit tables = 1024 words total.
constant CAM_TABLE_SIZE : integer := 4 * 256;

-- Define convenience types:
subtype cam_ridx is integer range 0 to 3;
subtype cam_addr is unsigned(9 downto 0);
subtype cam_word is std_logic_vector(TABLE_SIZE-1 downto 0);
subtype table_addr is unsigned(TABLE_IDX_WIDTH-1 downto 0);

-- Wrapper for the standard one-hot-decode function, converts
-- one-hot table-index to the address of the first metadata byte.
function one_hot_decode2(x : cam_word) return table_addr is
    variable tmp : table_addr := one_hot_decode(x, TABLE_IDX_WIDTH);
begin
    return shift_left(tmp, TABLE_META_SHIFT);
end function;

-- Create CAM-lookup address from value of the Nth IPv4 address byte.
function make_camaddr(phase:cam_ridx; addr:byte_t) return cam_addr is
begin
    return to_unsigned(256*phase + u2i(addr), 10);
end function;

-- CAM control for forward queries.
constant QUERY_STATE_MAX : integer := 12;
signal query_state  : integer range 0 to QUERY_STATE_MAX := 0;
signal query_ridx   : cam_ridx := 0;
signal query_raw    : cam_word := (others => '0');
signal query_mask   : cam_word := (others => '0');
signal query_taddr  : table_addr := (others => '0');
signal query_tfound : std_logic := '0';

-- CAM control for updates and evictions.
constant WRITE_STATE_MAX : integer := 21;
signal write_state  : integer range 0 to WRITE_STATE_MAX := 0;
signal write_ce     : std_logic := '0';
signal write_mask   : cam_word := (others => '0');
signal write_count  : integer range 0 to TABLE_SIZE := 0;
signal write_next   : integer range 0 to TABLE_SIZE-1 := 0;
signal write_taddr  : table_addr := (others => '0');
signal write_tfound : std_logic := '0';
signal write_tevict : std_logic := '0';

signal camrd_addr   : cam_addr := (others => '0');
signal camrd_raw    : cam_word := (others => '0');
signal camwr_addr   : cam_addr := (others => '0');
signal camwr_mask   : cam_word := (others => '0');
signal camwr_en     : std_logic := '0';

-- Address table control.
signal tbl_wr_en    : std_logic := '0';
signal tbl_wr_val   : byte_t := (others => '0');
signal tbl_wr_old   : byte_t := (others => '0');
signal tbl_rd_val   : byte_t := (others => '0');

-- Internal copies of external signals.
signal reply_first_i    : std_logic := '0';
signal reply_write_i    : std_logic := '0';
signal reply_match_i    : std_logic := '0';
signal reply_addr_i     : byte_t := (others => '0');
signal request_first_i  : std_logic := '0';
signal request_write_i  : std_logic := '0';
signal request_addr_i   : byte_t := (others => '0');

begin

-- Drive top-level outputs:
reply_first     <= reply_first_i;
reply_write     <= reply_write_i;
reply_match     <= reply_match_i;
reply_addr      <= reply_addr_i;
request_first   <= request_first_i;
request_write   <= request_write_i;
request_addr    <= request_addr_i;

-- Upstream flow control.
query_ready     <= bool2bit(query_state < 4);
update_ready    <= bool2bit(0 < write_state and write_state < 11);

-- Inferred three-port search RAM (one write, two read)
-- Each word is a search mask as described in Jiang's paper; because the
-- search is consecutive we can interleave each sub-table in one BRAM.
query_ridx  <= query_state when (query_state < 4) else 0;

p_cam_ram : process(clk)
    type cam_array is array(0 to CAM_TABLE_SIZE-1) of cam_word;
    variable dp_ram : cam_array := (others => (others => '0'));
begin
    if rising_edge(clk) then
        if (camwr_en = '1') then
            dp_ram(to_integer(camwr_addr)) := camwr_mask;
        end if;
        if (query_valid = '1') then
            query_raw <= dp_ram(to_integer(make_camaddr(query_ridx, query_addr)));
        end if;
        if (write_ce = '1') then
            camrd_raw <= dp_ram(to_integer(camrd_addr));
        end if;
    end if;
end process;

-- Inferred dual-port RAM for the address table.
-- Note: Read-before-write is used to simplify the eviction process.
p_tbl_ram : process(clk)
    constant TABLE_BYTES : integer := TABLE_SIZE * TABLE_META_BYTES;
    type tbl_array is array(0 to TABLE_BYTES-1) of byte_t;
    variable dp_ram : tbl_array := (others => (others => '0'));
begin
    if rising_edge(clk) then
        tbl_rd_val <= dp_ram(to_integer(query_taddr));
        if (tbl_wr_en = '1') then
            tbl_wr_old <= dp_ram(to_integer(write_taddr));
            dp_ram(to_integer(write_taddr)) := tbl_wr_val;
        end if;
    end if;
end process;

-- CAM control for forward queries.
-- Starting from the query_first strobe:
--  * Search CAM four consecutive cycles (for each byte of IPv4 address)
--  * AND each raw-mask together -> Match found? Index?
--  * If found:
--      Strobe reply_first + reply_match, read 6x MAC address from address table
--    Else:
--      Strobe reply_first + !reply_match, FF:FF:FF:FF:FF:FF
--      Strobe request_first + provide the original IPv4 address
p_ctrl_query : process(clk)
    variable addr_sreg : std_logic_vector(31 downto 0) := (others => '0');
begin
    if rising_edge(clk) then
        -- Update the state counter (0 = idle, 1-N = step count)
        if (reset_p = '1') then
            query_state <= 0;   -- Reset / idle
        elsif (query_state = 0) then
            -- Discard any leftover data until we get a "first" strobe.
            if (query_valid = '1' and query_first = '1') then
                query_state <= 1;   -- Start new
            end if;
        elsif (query_state < 4) then
            -- Increment as we receive each byte of query address.
            if (query_valid = '1') then
                query_state <= query_state + 1;
            end if;
        elsif (query_state < QUERY_STATE_MAX) then
            -- Auto-increment until done.
            query_state <= query_state + 1;
        else
            -- Done, revert to idle.
            query_state <= 0;
        end if;

        -- Bitwise AND of the first four CAM results.
        if (query_state = 0) then
            -- Set mask if table ready, otherwise clear to ensure no-match.
            query_mask <= (others => bool2bit(write_state > 0));
        elsif (1 <= query_state and query_state <= 4) then
            query_mask <= query_mask and query_raw;
        end if;

        -- Calculate the table index as soon as the CAM mask is ready.
        -- (i.e., Ready to start reading from start of MAC address.)
        if (query_state = 5) then
            -- Get ready to read first byte of MAC address...
            query_tfound <= or_reduce(query_mask);
            query_taddr  <= one_hot_decode2(query_mask) + META_OFFSET_MAC;
        elsif (query_state > 5) then
            -- Increment address after each byte.
            query_taddr  <= query_taddr + 1;
        end if;

        -- Emit the 6-byte MAC address reply, if found.
        reply_first_i <= bool2bit(query_state = 7);
        reply_write_i <= bool2bit(query_state >= 7);
        if (query_state < 7) then
            reply_match_i <= '0';   -- Between results
            reply_addr_i  <= (others => '0');
        elsif (query_tfound = '1') then
            reply_match_i <= '1';   -- Match found
            reply_addr_i  <= tbl_rd_val;
        else
            reply_match_i <= '0';   -- No match
            reply_addr_i  <= (others => '1');
        end if;

        -- If no match was found, request an ARP query.
        request_first_i <= bool2bit(query_tfound = '0' and query_state = 6);
        request_write_i <= bool2bit(query_tfound = '0' and 6 <= query_state and query_state < 10);
        request_addr_i  <= addr_sreg(31 downto 24); -- MSB first

        -- Update shift-register for replay of IPv4 address.
        if ((query_state < 4 and query_valid = '1') or (query_state > 5)) then
            addr_sreg := addr_sreg(23 downto 0) & query_addr;
        end if;
    end if;
end process;

-- CAM control for updates and evictions.
-- On startup:
--  * Clear the contents of the CAM table.
-- Starting from each update_first strobe:
--  * Search CAM four consecutive cycles (for each byte of IPv4 address)
--  * AND each raw-mask together -> Match found? Index?
--    Write index = Found or first empty
--  * Write new data to the table
--      16x write new address to selected row (4 IP, 6 MAC, 6 spare)
--      (This also reads the previous IP address, if needed for eviction)
--  * Concurrently, update CAM entry:
--      4x CAM read/modify/write to evict deleted entry, if required
--      4x CAM read/modify/write to insert the new entry
write_ce <= update_valid or bool2bit(write_state = 0 or write_state > 10);

p_ctrl_cam_wr : process(clk)
    variable sreg_ip  : std_logic_vector(31 downto 0) := (others => '0');
    variable sreg_old : std_logic_vector(15 downto 0) := (others => '0');
    variable sreg_tbl : std_logic_vector(47 downto 0) := (others => '0');
begin
    if rising_edge(clk) then
        -- Update the state counter (0 = idle, 1-N = step count)
        if (reset_p = '1') then
            -- On reset, begin clearing table.
            write_state <= 0;
        elsif (write_ce = '0') then
            -- Waiting for clock-enable...
            null;
        elsif (write_state = 0) then
            -- Wait until we've erased the entire CAM table.
            if (camwr_addr = CAM_TABLE_SIZE-1) then
                write_state <= 1;
            end if;
        elsif (write_state = 1) then
            -- Begin update once we get a "first" strobe.
            if (update_first = '1') then
                write_state <= 2;
            end if;
        elsif (write_state < WRITE_STATE_MAX) then
            -- Increment counter until end of cycle.
            write_state <= write_state + 1;
        else
            -- Done! Revert to idle.
            write_state <= 1;
        end if;

        -- At the end of each cycle, update the number of stored addresses
        -- and the next table index for appending or overwriting new data.
        if (reset_p = '1') then
            write_count <= 0;
            write_next  <= 0;
        elsif (write_ce = '1' and write_state = WRITE_STATE_MAX and write_tfound = '0') then
            if (write_count < TABLE_SIZE) then
                write_count <= write_count + 1;
            end if;
            if (write_next < TABLE_SIZE-1) then
                write_next <= write_next + 1;
            else
                write_next <= 0;
            end if;
        end if;

        -- Send each CAM write command.
        if (reset_p = '1') then
            -- Begin clearing table
            camwr_en   <= '1';
            camwr_addr <= (others => '0');
            camwr_mask <= (others => '0');
        elsif (write_state = 0) then
            -- Continue clearning table
            camwr_en   <= '1';
            camwr_addr <= camwr_addr + 1;
            camwr_mask <= (others => '0');
        elsif (10 <= write_state and write_state <= 13) then
            -- Read/modify/write old IPv4 address for eviction
            camwr_en   <= write_ce and write_tevict;
            camwr_addr <= make_camaddr(write_state-10, sreg_old(15 downto 8));
            camwr_mask <= camrd_raw and not write_mask;
        elsif (14 <= write_state and write_state <= 17) then
            -- Read/modify/write new IPv4 address for insertion
            camwr_en   <= write_ce and not write_tfound;
            camwr_addr <= make_camaddr(write_state-14, sreg_ip(15 downto 8));
            camwr_mask <= camrd_raw or write_mask;
        else
            camwr_en   <= '0';  -- Idle
        end if;

        -- Send each CAM read command.
        if (write_ce = '0') then
            null;
        elsif (write_state = 1 and update_first = '1') then
            -- Start of update sequence, initiate search.
            camrd_addr <= make_camaddr(0, update_addr);
        elsif (2 <= write_state and write_state <= 4) then
            -- Continue initial search.
            camrd_addr <= make_camaddr(write_state-1, update_addr);
        elsif (8 <= write_state and write_state <= 11) then
            -- Read/modify/write cycle to evict old entry, if required.
            -- Note: Old IPv4 address is being read from table during this phase.
            camrd_addr <= make_camaddr(write_state-8, tbl_wr_old);
        elsif (12 <= write_state and write_state <= 15) then
            -- Read/modify/write cycle to write new entry.
            camrd_addr <= make_camaddr(write_state-12, sreg_ip(31 downto 24));
        end if;

        -- Bitwise AND of the first four CAM results.
        if (write_state = 1 and update_first = '1') then
            -- Start of initial search, set initial state.
            write_mask <= (others => '1');
        elsif (3 <= write_state and write_state <= 6) then
            -- Bitwise AND for each step of the initial search.
            write_mask <= write_mask and camrd_raw;
        elsif (write_state = 8 and write_tfound = '0') then
            -- If no match, set mask to the next write index.
            write_mask(write_next) <= '1';
        end if;

        -- Update the table address and match/no-match flags.
        if (write_state = 7) then
            -- Calculate the table index as soon as the CAM mask is ready.
            -- (i.e., Get ready to start writing from start of entry.)
            if (or_reduce(write_mask) = '1') then
                -- Match found, update the corresponding address.
                write_tfound <= '1';
                write_tevict <= '0';
                write_taddr  <= one_hot_decode2(write_mask);
            else
                -- No match, create a new entry or evict/overwrite.
                write_tfound <= '0';
                write_tevict <= bool2bit(write_count = TABLE_SIZE);
                write_taddr  <= to_unsigned(16 * write_next, TABLE_IDX_WIDTH);
            end if;
        elsif (write_ce = '1' and write_state > 7) then
            -- Increment address while we write the full row.
            write_taddr <= write_taddr + 1;
        end if;

        -- Choose each value written to the address table.
        -- (4 byte IPv4, 6 byte MAC, 6 bytes reserved)
        tbl_wr_en <= write_ce and bool2bit(write_state >= 7);
        if (write_ce = '1') then
            tbl_wr_val <= sreg_tbl(47 downto 40);
        end if;

        -- Shift registers are used to delay/recall address fields.
        -- * sreg_ip:   New IP address (feed in, then loopback)
        -- * sreg_old:  Previous IP for clearing CAM (simple delay)
        -- * sreg_tbl:  New IP+MAC for writing table (simple delay)
        if (write_state < 5 and update_valid = '1') then
            sreg_ip := sreg_ip(23 downto 0) & update_addr;
        elsif (write_state >= 12) then
            sreg_ip := sreg_ip(23 downto 0) & sreg_ip(31 downto 24);
        end if;
        if (write_ce = '1') then
            sreg_old := sreg_old(7 downto 0) & tbl_wr_old;
            sreg_tbl := sreg_tbl(39 downto 0) & update_addr;
        end if;
    end if;
end process;

end router_arp_cache;
