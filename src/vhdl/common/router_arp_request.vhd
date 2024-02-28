--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Address Resolution Protocol (ARP) packet interface
--
-- This block handles byte-by-byte implementation of the Address Resolution
-- Protocol (IETF RFC 826), sending ARP requests for missing data whenever
-- the ARP-Cache has a missing entry.
--
-- To avoid flooding the network with ARP traffic, we implement a simple
-- rate-limiting system.  Each new requested address is compared against a
-- history of recent requests, and duplicates are discarded.  The history
-- queue is flushed over time to allow retry after a specified delay.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;

entity router_arp_request is
    generic (
    -- Set the MAC-address for the local interface.
    LOCAL_MACADDR   : mac_addr_t;
    -- Options for each output frame.
    ARP_APPEND_FCS  : boolean := false;
    MIN_FRAME_BYTES : natural := 0;
    -- Rate-limiter parameters.
    HISTORY_COUNT   : positive := 16;
    HISTORY_TIMEOUT : natural := 10_000_000);
    port (
    -- Network interface
    pkt_tx_data     : out byte_t;
    pkt_tx_last     : out std_logic;
    pkt_tx_valid    : out std_logic;
    pkt_tx_ready    : in  std_logic;

    -- Requests from ARP-Table
    request_first   : in  std_logic;    -- First-byte strobe
    request_addr    : in  byte_t;       -- IPv4 address
    request_write   : in  std_logic;

    -- Local address (required for ARP).
    router_ipaddr   : in  ip_addr_t;

    -- System clock and reset.
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end router_arp_request;

architecture router_arp_request of router_arp_request is

-- How many bytes in each ARP response? (Exclude CRC)
-- Minimum is 14 header + 28 ARP = 42 bytes.
function get_arplen return integer is
begin
    return int_max(42, MIN_FRAME_BYTES-4);
end function;
constant ARP_FRAME_BYTES : integer := get_arplen;

-- Convert byte-stream to IPv4 address, then hold until consumed.
signal next_addr    : ip_addr_t := (others => '0');
signal next_start   : std_logic := '0';
signal next_valid   : std_logic := '0';
signal next_ready   : std_logic := '0';

-- History is stored in an addressable shift-register.
signal hist_rdval   : ip_addr_t := (others => '0');
signal hist_wrnext  : std_logic := '0';
signal hist_wrzero  : std_logic := '0';

-- History-scanning state machine.
type scan_state_t is (SCAN_RESET, SCAN_IDLE, SCAN_EXEC, SCAN_WAIT);
signal scan_state   : scan_state_t := SCAN_RESET;
signal scan_rdidx   : integer range 0 to HISTORY_COUNT-1 := 0;
signal scan_done    : std_logic := '0';
signal scan_fail    : std_logic := '0';
signal scan_flush   : std_logic := '0';

-- Generate the ARP-Request packet.
signal tx_state     : integer range 0 to ARP_FRAME_BYTES-1 := 0;
signal tx_data      : byte_t := (others => '0');
signal tx_last      : std_logic := '0';
signal tx_valid     : std_logic := '0';
signal tx_ready     : std_logic := '0';
signal tx_done      : std_logic := '0';

begin

-- Convert byte-stream to IPv4 address, then hold until consumed.
next_ready <= scan_fail or tx_done;

p_next : process(clk)
    variable next_remct : integer range 0 to 3 := 0;
begin
    if rising_edge(clk) then
        -- Only accept new data between runs.
        if (request_write = '1' and next_valid = '0') then
            next_addr <= next_addr(23 downto 0) & request_addr;
        end if;

        -- Assert VALID flag and START strobe on the fourth valid byte.
        if (reset_p = '1' or next_ready = '1') then
            -- Global reset or previous address consumed.
            next_start <= '0';
            next_valid <= '0';
        elsif (next_remct = 1 and request_write = '1') then
            -- Transfer in progress, assert "valid" on the fourth byte.
            next_start <= '1';
            next_valid <= '1';
        else
            next_start <= '0';
        end if;

        -- Count off every four valid bytes.
        if (reset_p = '1') then
            -- Global reset.
            next_remct := 0;
        elsif (next_remct > 0 and request_write = '1') then
            -- Transfer in progress, countdown to zero.
            next_remct := next_remct - 1;
        elsif (next_valid = '0' and request_write = '1' and request_first = '1') then
            -- Start of a new address, start countdown.
            next_remct := 3;
        end if;
    end if;
end process;

-- History is stored in an addressable shift-register.
-- (Clean inferrence as SRL16E or similar, no runtime reset.)
hist_wrzero <= bool2bit(scan_state = SCAN_RESET) or scan_flush;
hist_wrnext <= scan_done;

p_hist : process(clk)
    type ip_array_t is array(0 to HISTORY_COUNT-1) of ip_addr_t;
    constant ADDR_ZERO  : ip_addr_t := (others => '0');
    variable hist_sreg  : ip_array_t := (others => ADDR_ZERO);
begin
    if rising_edge(clk) then
        hist_rdval <= hist_sreg(scan_rdidx);
        if (hist_wrnext = '1') then
            hist_sreg := next_addr & hist_sreg(0 to HISTORY_COUNT-2);
        elsif (hist_wrzero = '1') then
            hist_sreg := ADDR_ZERO & hist_sreg(0 to HISTORY_COUNT-2);
        end if;
    end if;
end process;

-- History-scanning state machine.
p_scan : process(clk)
    constant WDOG_MAX : integer := HISTORY_TIMEOUT / HISTORY_COUNT;
    variable wdog_ctr : integer range 0 to WDOG_MAX := WDOG_MAX;
    variable last_idx : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Main scanning state machine.
        if (reset_p = '1') then
            -- Global reset.
            scan_state <= SCAN_RESET;
        elsif (scan_fail = '1' or tx_done = '1') then
            -- Done, revert to idle.
            scan_state <= SCAN_IDLE;
        elsif (scan_state = SCAN_RESET and scan_rdidx = HISTORY_COUNT-1) then
            -- Hold in RESET until shift register is flushed.
            scan_state <= SCAN_IDLE;
        elsif (scan_state = SCAN_IDLE and next_valid = '1') then
            -- Received adddress, start new scan.
            scan_state <= SCAN_EXEC;
        elsif (scan_state = SCAN_EXEC and hist_rdval = next_addr) then
            -- Scan failed, revvert to idle.
            scan_state <= SCAN_IDLE;
        elsif (scan_state = SCAN_EXEC and last_idx = '1') then
            -- Scan completed, wait for DONE.
            scan_state <= SCAN_WAIT;
        end if;

        -- Drive the DONE and FAIL strobes.
        if (scan_state = SCAN_EXEC) then
            scan_done <= last_idx and bool2bit(hist_rdval /= next_addr);
            scan_fail <= bool2bit(hist_rdval = next_addr);
        else
            scan_done <= '0';
            scan_fail <= '0';
        end if;

        -- Scan through addresses during RESET or EXEC states.
        if (reset_p = '1' or scan_fail = '1' or scan_done = '1') then
            scan_rdidx <= 0;                -- Reset
        elsif (scan_rdidx = HISTORY_COUNT-1) then
            scan_rdidx <= 0;                -- Wraparound
        elsif (scan_state = SCAN_RESET) then
            scan_rdidx <= scan_rdidx + 1;   -- Continue startup flush
        elsif (scan_state = SCAN_IDLE and next_valid = '1') then
            scan_rdidx <= scan_rdidx + 1;   -- Start of new scan
        elsif (scan_state = SCAN_EXEC and scan_rdidx > 0) then
            scan_rdidx <= scan_rdidx + 1;   -- Continue scan
        end if;

        -- Background timer for flushing old values.
        scan_flush <= bool2bit(wdog_ctr = 0);
        if (reset_p = '1' or wdog_ctr = 0) then
            wdog_ctr := WDOG_MAX;
        else
            wdog_ctr := wdog_ctr - 1;
        end if;

        -- Last-index flag is driven after a one-cycle delay.
        -- (Matches delay from scan_rdidx to hist_rdval.)
        last_idx := bool2bit(scan_rdidx = HISTORY_COUNT-1);
    end if;
end process;

-- Generate the ARP-Request packet.
tx_done <= tx_valid and tx_last and tx_ready;

p_tx : process(clk)
    -- Fixed fields: EtherType, HTYPE, PTYPE, HLEN, PLEN, OPER
    constant ARP_FIXED_HDR : std_logic_vector(79 downto 0) :=
        x"0806_0001_0800_06_04_0001";
begin
    if rising_edge(clk) then
        -- Send each byte in the response frame:
        if (scan_done = '1' or tx_ready = '1') then
            tx_last <= bool2bit(tx_state = ARP_FRAME_BYTES-1);
            if (tx_state < 6) then      -- Destination MAC
                tx_data <= get_byte_s(MAC_ADDR_BROADCAST, 5-tx_state);
            elsif (tx_state < 12) then  -- Source MAC
                tx_data <= get_byte_s(LOCAL_MACADDR, 11-tx_state);
            elsif (tx_state < 22) then  -- Fixed fields (see above)
                tx_data <= get_byte_s(ARP_FIXED_HDR, 21-tx_state);
            elsif (tx_state < 28) then  -- Request SHA = Our MAC
                tx_data <= get_byte_s(LOCAL_MACADDR, 27-tx_state);
            elsif (tx_state < 32) then  -- Request SPA = Router IP
                tx_data <= get_byte_s(router_ipaddr, 31-tx_state);
            elsif (tx_state < 38) then  -- Request THA = Filler
                tx_data <= (others => '1');
            elsif (tx_state < 42) then  -- Request TPA = Target IP
                tx_data <= get_byte_s(next_addr, 41-tx_state);
            else                        -- Zero-pad (optional)
                tx_data <= (others => '0');
            end if;
        end if;

        -- Data-valid flag is set by the SCAN_DONE strobe, then held high
        -- until the next downstream block accepts the final byte.
        if (reset_p = '1') then
            tx_valid <= '0';
        elsif (scan_done = '1') then
            tx_valid <= '1';
        elsif (tx_state = 0 and tx_ready = '1') then
            assert (tx_valid = '0' or tx_last = '1')
                report "Missing LAST strobe." severity error;
            tx_valid <= '0';
        end if;

        -- State counter is the byte offset for the NEXT byte to be sent.
        -- Increment it as soon as we've latched each value, above.
        if (reset_p = '1') then
            tx_state <= 0;      -- Reset to idle state.
        elsif ((scan_done = '1') or (tx_state > 0 and tx_ready = '1')) then
            if (tx_state = ARP_FRAME_BYTES-1) then
                tx_state <= 0;  -- Done, revert to idle.
            else
                tx_state <= tx_state + 1;
            end if;
        end if;
    end if;
end process;

-- (Optional) Append FCS/CRC32 to each frame.
gen_crc : if ARP_APPEND_FCS generate
    u_crc : entity work.eth_frame_adjust
        generic map(
        MIN_FRAME   => 0,               -- Padding disabled (handled above)
        APPEND_FCS  => ARP_APPEND_FCS,  -- Append FCS to final output?
        STRIP_FCS   => false)           -- No FCS to be stripped
        port map(
        in_data     => tx_data,
        in_last     => tx_last,
        in_valid    => tx_valid,
        in_ready    => tx_ready,
        out_data    => pkt_tx_data,
        out_last    => pkt_tx_last,
        out_valid   => pkt_tx_valid,
        out_ready   => pkt_tx_ready,
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_nocrc : if not ARP_APPEND_FCS generate
    pkt_tx_data  <= tx_data;
    pkt_tx_last  <= tx_last;
    pkt_tx_valid <= tx_valid;
    tx_ready     <= pkt_tx_ready;
end generate;

end router_arp_request;
