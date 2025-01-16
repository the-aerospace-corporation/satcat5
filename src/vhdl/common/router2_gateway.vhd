--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- IPv4 gateway and packet-routing logic
--
-- This block inspects IPv4 packets, detects various error conditions,
-- queries the routing table, attempts to determine the next-hop MAC
-- address, and determines if offload processing is required.
--
-- The design is intended to comply with IETF RFC-1812, with some exceptions:
--  "Requirements for IP Version 4 Routers" https://www.rfc-editor.org/rfc/rfc1812
--  * No support for fragmentation, because input and output have the same MTU.
--  * No support for LSR or SSR options.
--  * No support for SNMP.
--
-- The overall decision tree is as follows:
--  * ARP frames (EtherType = 0x0806):
--      * Always forwarded to offload port.
--  * IPv4 frames (EtherType = 0x0800):
--      * If header parameters violate RFC1812 rules, drop the frame.
--      * If TTL = 0, forward to offload port.
--        (Offload processing should reply with ICMP "time exceeded" error.)
--      * Inspect the destination IP address and lookup in the routing table:
--          * If destination IP is the router itself, forward to offload port.
--          * If destination and source ports are the same, CC to offload port.
--          * If next-hop MAC address and port are known, forward accordingly.
--          * Otherwise, foward to offload port for deferred handling.
--  * Other frame types:
--      * If ALLOW_NOIP is enabled, forward to offload port.
--      * Otherwise, drop the frame.
--
-- A separate block (i.e., "router2_offload") interfaces with the offload
-- port, updates the source and destination MAC, and decrements the TTL.
--
-- All input and output streams contain Ethernet frames with no FCS and
-- no VLAN tags.  Output metadata is available from start-of-frame.
--
-- Configuration is managed through several ConfigBus registers:
--  RT_ADDR_GATEWAY: Configure selected rules and the router address.
--      1st Write:
--          Bits 31-22: Reserved
--          Bit  21:    Do not relay IPv4 broadcasts to the offload port.
--          Bit  20:    Drop non-IPv4 broadcast packets.
--          Bit  19:    Drop all non-IPv4 packets except ARP.
--          Bit  18:    Drop all IPv4 multicast packets.
--          Bit  17:    Drop all IPv4 local-broadcast packets.
--          Bit  16:    Drop unexpected destination MAC.
--          Bits 15-00: MSBs of Router MAC address.
--      2nd Write:
--          Bits 31-00: LSBs of Router MAC address.
--      3rd Write:
--          Bits 31-00: Router IP-address
--      Write x 3, then read to load the new configuration.
--  RT_ADDR_PORT_SHDN: Link status for each port (read-only).
--      Bits 31-00: Link-down (1) or link-up (0) mask for each port.
--  RT_ADDR_CIDR_CTRL: See router2_table.vhd
--  RT_ADDR_CIDR_DATA: See router2_table.vhd
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.router2_common.all;
use     work.switch_types.all;

entity router2_gateway is
    generic (
    DEVADDR     : integer;              -- ConfigBus address
    IO_BYTES    : positive;             -- Width of datapath
    PORT_COUNT  : positive;             -- Number of ports
    TABLE_SIZE  : positive;             -- Size of routing table
    DEFAULT_MAC : mac_addr_t := (others => '0');
    DEFAULT_IP  : ip_addr_t := (others => '0');
    DEFAULT_BLK : std_logic_vector(15 downto 0) := (others => '1');
    VERBOSE     : boolean := false);    -- Enable simulation logs?
    port (
    -- Input stream with AXI-stream flow control.
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;
    in_psrc     : in  integer range 0 to PORT_COUNT-1;
    in_meta     : in  switch_meta_t;

    -- Output stream with AXI-stream flow control.
    -- (Offload port is indicated by MSB of out_dstmask.)
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;
    out_dstmac  : out mac_addr_t;
    out_srcmac  : out mac_addr_t;
    out_pdst    : out std_logic_vector(PORT_COUNT downto 0);
    out_psrc    : out integer range 0 to PORT_COUNT-1;
    out_meta    : out switch_meta_t;
    tcam_error  : out std_logic;

    -- Port-status indicators (optional, asynchronous)
    port_shdn   : in  std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');

    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;

    -- System clock and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end router2_gateway;

architecture router2_gateway of router2_gateway is

-- Define internal codes for packet-parsing decisions:
constant ACT_WIDTH      : integer := 2;
subtype action_t is std_logic_vector(ACT_WIDTH-1 downto 0);
constant ACT_DROP       : action_t := i2s(0, ACT_WIDTH);    -- Silently drop frame
constant ACT_FORWARD    : action_t := i2s(1, ACT_WIDTH);    -- Forward frame (CIDR)
constant ACT_OFFLOAD    : action_t := i2s(2, ACT_WIDTH);    -- Offload frame
constant ACT_BROADCAST  : action_t := i2s(3, ACT_WIDTH);    -- Broadcast frame

-- Total metadata width for the primary FIFO.
constant PSRC_WIDTH     : integer := log2_ceil(PORT_COUNT);
constant META1_WIDTH    : integer := PSRC_WIDTH + SWITCH_META_WIDTH;
constant META2_WIDTH    : integer := PSRC_WIDTH + ACT_WIDTH;
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype meta1_t is std_logic_vector(META1_WIDTH-1 downto 0);
subtype meta2_t is std_logic_vector(META2_WIDTH-1 downto 0);
subtype pmask_in_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype pmask_out_t is std_logic_vector(PORT_COUNT downto 0);
subtype psrc_t is std_logic_vector(PSRC_WIDTH-1 downto 0);
subtype psrc_u is unsigned(PSRC_WIDTH-1 downto 0);

-- Maximum byte-index of interest is the end of the IPv4 header.
-- (We don't care about options, but do need to verify the header checksum.)
constant WCOUNT_END : integer := IP_HDR_MAX / IO_BYTES;
constant WCOUNT_MAX : integer := WCOUNT_END + 1;
subtype counter_t is integer range 0 to WCOUNT_MAX;

-- Convert port-index to a destination mask.
function idx2mask(x: natural) return pmask_out_t is
    constant PORT_ZERO : pmask_out_t := i2s(1, PORT_COUNT + 1);
begin
    return shift_left(PORT_ZERO, x);
end function;

-- Calculate the required FIFO depth:
--  * Initial parsing delay = 34 / IO_BYTES cycles
--    (Parser can't decide until end of IPv4 header.)
--  * Routing table lookup = 5 + log2(TABLE_SIZE) cycles
--  * Additional pipeline delay = 2
function FIFO_DEPTH_LOG2 return positive is
    constant MAX_DELAY : positive :=
        div_ceil(IP_HDR_MIN, IO_BYTES) + 7 + log2_ceil(TABLE_SIZE);
begin
    if (MAX_DELAY < 16) then
        return 4;
    else
        return log2_ceil(MAX_DELAY);
    end if;
end function;

-- Input conversions and matched-delay FIFO.
signal in_write     : std_logic;
signal in_full      : std_logic;
signal in_mvec      : meta1_t;
signal dly_data     : data_t;
signal dly_nlast    : integer range 0 to IO_BYTES;
signal dly_valid    : std_logic;
signal dly_ready    : std_logic;
signal dly_mvec     : meta1_t;

-- Header checksum validation.
signal chk_data     : data_t;
signal chk_psrc     : psrc_t;
signal chk_nlast    : integer range 0 to IO_BYTES;
signal chk_write    : std_logic;
signal chk_match    : std_logic;
signal chk_error    : std_logic;

-- Header parsing state machine.
signal chk_wcount   : counter_t := 0;
signal pkt_dst_ip   : ip_addr_t := (others => '0');
signal pkt_mvec     : meta2_t := (others => '0');
signal pkt_next     : std_logic := '0';
signal pkt_done     : std_logic := '0';

-- Routing table.
signal tbl_found    : std_logic;
signal tbl_next     : std_logic;
signal tbl_mvec     : meta2_t;
signal tbl_action   : action_t;
signal tbl_dstmac   : mac_addr_t;
signal tbl_dstmask  : pmask_out_t;
signal tbl_shdn     : pmask_out_t;
signal tbl_pdst     : byte_u;
signal tbl_psrc     : byte_u;
signal tbl_offload  : std_logic;
signal safe_bcast   : pmask_out_t;

-- Final decision and metadata FIFO.
signal dst_mac      : mac_addr_t := (others => '0');
signal dst_mask     : pmask_out_t := (others => '0');
signal dst_next     : std_logic := '0';
signal dst_valid    : std_logic;
signal dst_ready    : std_logic;

-- Status indicators and clock-domain crossings.
signal port_shdn_i  : pmask_in_t;
signal port_shdn_c  : pmask_in_t;
signal cfg_shutdown : cfgbus_word;

-- ConfigBus interface.
subtype cfg_t is std_logic_vector(95 downto 0);
constant CFG_RESET  : cfg_t := DEFAULT_BLK & DEFAULT_MAC & DEFAULT_IP;
signal cfg_word     : cfg_t := CFG_RESET;
signal cfg_acks     : cfgbus_ack_array(0 to 2);
signal cfg_macaddr  : mac_addr_t;
signal cfg_ipaddr   : ip_addr_t;

-- Break out specific rules from cfg_word.
signal block_bad_dmac   : std_logic;    -- Default = 1
signal block_ipv4_bcast : std_logic;    -- Default = 1
signal block_ipv4_mcast : std_logic;    -- Default = 1
signal block_noip_bcast : std_logic;    -- Default = 1
signal block_noip_all   : std_logic;    -- Default = 1
signal block_lcl_bcast  : std_logic;    -- Default = 1

begin

-- Connect top-level outputs and convert metadata formats.
in_ready    <= not in_full;
in_write    <= in_valid and not in_full;
in_mvec     <= switch_m2v(in_meta) & i2s(in_psrc, PSRC_WIDTH);
out_data    <= dly_data;
out_nlast   <= dly_nlast;
out_srcmac  <= cfg_macaddr;
out_psrc    <= u2i(dly_mvec(PSRC_WIDTH-1 downto 0));
out_meta    <= switch_v2m(dly_mvec(dly_mvec'left downto PSRC_WIDTH));

-- Output flow control waits for both streams to be ready.
out_valid   <= dly_valid and dst_valid;
dly_ready   <= dly_valid and dst_valid and out_ready;
dst_ready   <= dly_ready and bool2bit(dly_nlast > 0);

-- A small FIFO acts as a matched delay for the main datapath.
u_data : entity work.fifo_smol_bytes
    generic map(
    DEPTH_LOG2  => FIFO_DEPTH_LOG2,
    IO_BYTES    => IO_BYTES,
    META_WIDTH  => META1_WIDTH)
    port map(
    in_data     => in_data,
    in_meta     => in_mvec,
    in_nlast    => in_nlast,
    in_write    => in_write,
    out_data    => dly_data,
    out_meta    => dly_mvec,
    out_nlast   => dly_nlast,
    out_valid   => dly_valid,
    out_read    => dly_ready,
    fifo_full   => in_full,
    clk         => clk,
    reset_p     => reset_p);

-- IP header checksum validation.
-- ("Match" or "error" strobe is concurrent with end of IPv4 header.)
u_chksum : entity work.router2_ipchksum
    generic map(
    IO_BYTES    => IO_BYTES,
    ADJ_MODE    => false,
    META_WIDTH  => PSRC_WIDTH)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_meta     => in_mvec(PSRC_WIDTH-1 downto 0),
    in_write    => in_write,
    early_match => chk_match,
    early_error => chk_error,
    out_data    => chk_data,
    out_nlast   => chk_nlast,
    out_meta    => chk_psrc,
    out_write   => chk_write,
    out_match   => open,
    clk         => clk,
    reset_p     => reset_p);

-- Parse Ethernet and IPv4 header fields.
p_parse : process(clk)
    -- Execute packet-routing decision, with specified reason.
    -- If the VERBOSE flag is set, the reason is printed to console.
    impure function execute(x: string) return std_logic is
    begin
        if (VERBOSE and chk_write = '1' and pkt_done = '0') then
            report x severity note;
        end if;
        return chk_write and not pkt_done;
    end function;

    -- Temporary variables for storing the output of read* functions.
    variable tmp8   : std_logic_vector(7 downto 0);
    variable tmp16  : std_logic_vector(15 downto 0);
    variable tmp32  : std_logic_vector(31 downto 0);
    variable tmp48  : std_logic_vector(47 downto 0);

    -- Thin wrapper for the stream-to-byte extractor function.
    impure function read8(bidx : natural) return boolean is
    begin
        tmp8 := strm_byte_value(IO_BYTES, bidx, chk_data);
        return strm_byte_present(IO_BYTES, bidx, chk_wcount);
    end function;

    -- First byte in each word resets all "tmp*" accumulators.
    -- This ensures sequential logic never chains between fields.
    impure function read0(bidx : natural) return boolean is
        variable match : boolean := read8(bidx);
    begin
        if match then
            tmp16 := (others => '0');
            tmp32 := (others => '0');
            tmp48 := (others => '0');
        end if;
        return match;
    end function;

    -- Accumulate fields over multiple bytes.
    -- (These functions work for IO_BYTES = 1 or IO_BYTES = 256).
    impure function read16(bidx : natural) return boolean is
    begin
        if read0(bidx + 0) then tmp16(15 downto 8) := tmp8; end if;
        if read8(bidx + 1) then tmp16( 7 downto 0) := tmp8; end if;
        return strm_byte_present(IO_BYTES, bidx + 1, chk_wcount);
    end function;

    impure function read32(bidx : natural) return boolean is
    begin
        if read0(bidx + 0) then tmp32(31 downto 24) := tmp8; end if;
        if read8(bidx + 1) then tmp32(23 downto 16) := tmp8; end if;
        if read8(bidx + 2) then tmp32(15 downto  8) := tmp8; end if;
        if read8(bidx + 3) then tmp32( 7 downto  0) := tmp8; end if;
        return strm_byte_present(IO_BYTES, bidx + 3, chk_wcount);
    end function;

    impure function read48(bidx : natural) return boolean is
    begin
        if read0(bidx + 0) then tmp48(47 downto 40) := tmp8; end if;
        if read8(bidx + 1) then tmp48(39 downto 32) := tmp8; end if;
        if read8(bidx + 2) then tmp48(31 downto 24) := tmp8; end if;
        if read8(bidx + 3) then tmp48(23 downto 16) := tmp8; end if;
        if read8(bidx + 4) then tmp48(15 downto  8) := tmp8; end if;
        if read8(bidx + 5) then tmp48( 7 downto  0) := tmp8; end if;
        return strm_byte_present(IO_BYTES, bidx + 5, chk_wcount);
    end function;

    -- Additional parsing flags.
    variable dmac_is_bcast  : boolean := false;
    variable dmac_is_mcast  : boolean := false;
    variable dst_is_mcast   : boolean := false;
    variable dst_is_self    : boolean := false;
    variable etype_is_ipv4  : boolean := false;
    variable ihl            : integer range 0 to 60 := 0;
    variable cmd            : action_t := ACT_DROP;
    variable rdy            : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Count current position in each input packet.
        if (reset_p = '1') then
            chk_wcount <= 0; -- Global reset
        elsif (chk_write = '1' and chk_nlast > 0) then
            chk_wcount <= 0; -- Start of new packet
        elsif (chk_write = '1' and chk_wcount < WCOUNT_MAX) then
            chk_wcount <= chk_wcount + 1;
        end if;

        -- Parse each input word.  For IO_BYTES > 1, several fields may
        -- arrive in the same clock cycle, so work from top to bottom.
        -- Multiple concurrent ACT_DROP is OK, otherwise avoid overwrite.
        cmd := (others => 'X'); rdy := '0'; -- Default = no change
        if (read48(ETH_HDR_DSTMAC)) then
            -- Destination MAC = Bytes 0-5.
            dmac_is_bcast := mac_is_broadcast(tmp48);
            dmac_is_mcast := dmac_is_bcast or mac_is_l3multicast(tmp48);
            if (mac_is_invalid(tmp48) or mac_is_l2multicast(tmp48)) then
                cmd := ACT_DROP;        -- Block (illegal destination)
                rdy := execute("DROP: Non-forwarding destination MAC");
            elsif (dmac_is_bcast or dmac_is_mcast or tmp48 = cfg_macaddr) then
                null;                   -- Valid DMAC = Decide later
            elsif (block_bad_dmac = '1') then
                cmd := ACT_DROP;        -- Blocked by policy
                rdy := execute("DROP: Unmatched destination MAC");
            end if;
        end if;

        if (read48(ETH_HDR_SRCMAC)) then
            -- Source MAC = Bytes 6-11.
            if (mac_is_broadcast(tmp48) or mac_is_l2multicast(tmp48) or mac_is_l3multicast(tmp48)) then
                cmd := ACT_DROP;        -- Block (Illegal source)
                rdy := execute("DROP: Illegal source MAC");
            end if;
        end if;

        if (read16(ETH_HDR_ETYPE)) then
            -- EtherType = Bytes 12-13.
            etype_is_ipv4 := (tmp16 = ETYPE_IPV4);
            if (rdy = '1') then
                null;                   -- Decision is already made
            elsif (tmp16 = ETYPE_IPV4) then
                null;                   -- IPv4 = Decide later
            elsif (tmp16 = ETYPE_ARP) then
                cmd := ACT_OFFLOAD;     -- ARP = Always offload
                rdy := execute("OFFLOAD: ARP message");
            elsif (block_noip_all = '1') then
                cmd := ACT_DROP;        -- Blocked by policy
                rdy := execute("DROP: Raw Ethernet");
            elsif (block_noip_bcast = '1' and dmac_is_bcast) then
                cmd := ACT_DROP;        -- Blocked by policy
                rdy := execute("DROP: Raw broadcast");
            else
                cmd := ACT_OFFLOAD;     -- Allowed non-IPv4.
                rdy := execute("OFFLOAD: Raw Ethernet");
            end if;
        end if;

        if (etype_is_ipv4 and read8(IP_HDR_VERSION)) then
            -- IP version and header length (IHL) = Byte 14.
            ihl := 4 * u2i(tmp8(3 downto 0));
            if (tmp8(7 downto 4) /= x"4") then
                cmd := ACT_DROP;        -- Unsupported IP version
                rdy := execute("DROP: Unsupported IP version");
            elsif (ihl < 20) then
                cmd := ACT_DROP;        -- Invalid IP header length
                rdy := execute("DROP: Invalid IHL");
            end if;
        end if;

        if (etype_is_ipv4 and read16(IP_HDR_TOTAL_LEN)) then
            -- IP total length (header + contents) = Bytes 16-17
            if (unsigned(tmp16) < ihl) then
                cmd := ACT_DROP;        -- Total length less than IHL
                rdy := execute("DROP: Invalid TLEN");
            end if;
        end if;

        if (etype_is_ipv4 and read8(IP_HDR_TTL)) then
            -- TTL = Byte 22.
            if (tmp8 = x"00") then
                cmd := ACT_OFFLOAD;     -- Reply with ICMP error
                rdy := execute("OFFLOAD: Time exceeded");
            end if;
        end if;

        if (etype_is_ipv4 and read32(IP_HDR_SRCADDR)) then
            -- IP source address = Bytes 26-29
            if (ip_is_broadcast(tmp32) or ip_is_multicast(tmp32) or ip_is_reserved(tmp32)) then
                cmd := ACT_DROP;        -- Blocked (Illegal source)
                rdy := execute("DROP: Illegal source IP");
            elsif (cfg_ipaddr = tmp32) then
                cmd := ACT_DROP;        -- Blocked (Illegal source)
                rdy := execute("DROP: Illegal source IP");
            end if;
        end if;

        if (etype_is_ipv4 and read32(IP_HDR_DSTADDR)) then
            -- IP destination address = Bytes 30-33
            pkt_dst_ip   <= tmp32;      -- Note destination address
            dst_is_mcast := ip_is_broadcast(tmp32) or ip_is_multicast(tmp32);
            dst_is_self  := (cfg_ipaddr = tmp32);
            if (ip_is_reserved(tmp32)) then
                cmd := ACT_DROP;        -- Blocked (RFC 1812 section 4.2.3.1)
                rdy := execute("DROP: Reserved IP");
            elsif (block_ipv4_bcast = '1' and ip_is_broadcast(tmp32)) then
                cmd := ACT_DROP;        -- Blocked by policy
                rdy := execute("DROP: Broadcast IP");
            elsif (block_ipv4_mcast = '1' and ip_is_multicast(tmp32)) then
                cmd := ACT_DROP;        -- Blocked by policy
                rdy := execute("DROP: Multicast IP");
            elsif (dmac_is_mcast and not ip_is_multicast(tmp32)) then
                cmd := ACT_DROP;        -- Blocked (RFC 1812 section 4.2.3.1)
                rdy := execute("DROP: MAC mcast must be IP mcast");
            end if;
        elsif (chk_wcount = 0) then
            pkt_dst_ip <= (others => '0');
        end if;

        -- If we've somehow made it this far, validate the IP header checksum.
        -- (Match or error strobe occurs on or after the end of IP_HDR_DSTADDR).
        if (chk_error = '1') then
            cmd := ACT_DROP;
            rdy := execute("DROP: Checksum mismatch");
        elsif (chk_match = '0' and chk_nlast > 0) then
            cmd := ACT_DROP;
            rdy := execute("DROP: Unexpected end-of-frame");
        elsif (chk_match = '0' or rdy = '1') then
            null;   -- Don't overwrite a previous "drop" decision.
        elsif (dst_is_mcast) then
            -- TODO: Implement proper IGMP snooping?
            cmd := ACT_BROADCAST;
            rdy := execute("FORWARD: Broadcast");
        elsif (dst_is_self) then
            cmd := ACT_OFFLOAD;
            rdy := execute("FORWARD: Self");
        else
            cmd := ACT_FORWARD;
            rdy := execute("FORWARD: Unicast");
        end if;

        -- Start the routing table query once action is decided.
        -- (Run exactly one query for each packet, see below.)
        if (pkt_done = '0' and rdy = '1') then
            pkt_mvec <= cmd & chk_psrc;
            pkt_next <= not reset_p;
        else
            pkt_next <= '0';
        end if;

        -- Sticky "done" flag helps prevent duplicates.
        -- (And gives us a sanity check that a decision was made.)
        if (reset_p = '1') then
            pkt_done <= '0';    -- Global reset
        elsif (chk_write = '1' and chk_nlast > 0) then
            assert (rdy = '1' or pkt_done = '1')
                report "Packet without action." severity error;
            pkt_done <= '0';    -- End-of-frame
        elsif (rdy = '1') then
            pkt_done <= '1';    -- Query start
        end if;
    end if;
end process;

-- Once we've decided the action (i.e., drop/forward/offload/broadcast),
-- query the routing table with the designated destination address.
u_table : entity work.router2_table
    generic map(
    DEVADDR     => DEVADDR,
    TABLE_SIZE  => TABLE_SIZE,
    META_WIDTH  => META2_WIDTH)
    port map(
    in_dst_ip   => pkt_dst_ip,
    in_next     => pkt_next,
    in_meta     => pkt_mvec,
    out_dst_ip  => open,
    out_dst_idx => tbl_pdst,
    out_dst_mac => tbl_dstmac,
    out_found   => tbl_found,
    out_next    => tbl_next,
    out_meta    => tbl_mvec,
    tcam_error  => tcam_error,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(0),
    clk         => clk,
    reset_p     => reset_p);

tbl_action  <= tbl_mvec(tbl_mvec'left downto PSRC_WIDTH);
tbl_dstmask <= idx2mask(u2i(tbl_pdst));
tbl_offload <= or_reduce(tbl_dstmask and tbl_shdn)      -- Port is in shutdown?
            or not tbl_found;                           -- Unreachable or unknown MAC
tbl_psrc    <= resize(unsigned(tbl_mvec(PSRC_WIDTH-1 downto 0)), 8);
tbl_shdn    <= '0' & port_shdn_i;                       -- Add the offload port

-- Prevent broadcast/multicast loopback to the source port.
safe_bcast  <= not one_hot_encode(to_integer(tbl_psrc), PORT_COUNT+1);

-- Final outcome is based on the search result.
p_decide : process(clk)
    constant OFFLOAD_MASK : pmask_out_t := idx2mask(PORT_COUNT);
begin
    if rising_edge(clk) then
        dst_next <= tbl_next and not reset_p;
        if (tbl_action = ACT_FORWARD and tbl_offload = '1') then
            -- Software handles deferred forwarding or ICMP errors.
            dst_mac  <= cfg_macaddr;
            dst_mask <= OFFLOAD_MASK;
        elsif (tbl_action = ACT_FORWARD and tbl_pdst = tbl_psrc) then
            -- Unicast forwarding back to the source port?
            -- (Carbon-copy to the offload port triggers ICMP redirect.)
            dst_mac  <= tbl_dstmac;
            dst_mask <= tbl_dstmask or OFFLOAD_MASK;
        elsif (tbl_action = ACT_FORWARD) then
            -- Normal unicast forwarding.
            dst_mac  <= tbl_dstmac;
            dst_mask <= tbl_dstmask;
        elsif (tbl_action = ACT_OFFLOAD) then
            -- Offload to software, ignore search result.
            dst_mac  <= cfg_macaddr;
            dst_mask <= OFFLOAD_MASK;
        elsif (tbl_action = ACT_BROADCAST and block_lcl_bcast = '1') then
            -- Restricted broadcast mode, skip the offload port.
            dst_mac  <= MAC_ADDR_BROADCAST;
            dst_mask <= safe_bcast and not OFFLOAD_MASK;
        elsif (tbl_action = ACT_BROADCAST) then
            -- Normal broadcast mode, all ports except loopback.
            dst_mac  <= MAC_ADDR_BROADCAST;
            dst_mask <= safe_bcast;
        else
            -- Otherwise, drop this packet.
            dst_mac  <= (others => '0');
            dst_mask <= (others => '0');
        end if;
    end if;
end process;

-- A small FIFO stores the result for each packet.
-- (Output is recombined with the buffered data stream.)
u_meta : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => MAC_ADDR_WIDTH,
    META_WIDTH  => PORT_COUNT+1)
    port map(
    in_data     => dst_mac,
    in_meta     => dst_mask,
    in_write    => dst_next,
    out_data    => out_dstmac,
    out_meta    => out_pdst,
    out_valid   => dst_valid,
    out_read    => dst_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Synchronize the asynchronous port-status indicators.
u_shdn_i : sync_buffer_slv
    generic map(IO_WIDTH => PORT_COUNT)
    port map(
    in_flag     => port_shdn,
    out_flag    => port_shdn_i,
    out_clk     => clk);
u_shdn_c : sync_buffer_slv
    generic map(IO_WIDTH => PORT_COUNT)
    port map(
    in_flag     => port_shdn,
    out_flag    => port_shdn_c,
    out_clk     => cfg_cmd.clk);

cfg_shutdown <= resize(port_shdn_c, CFGBUS_WORD_SIZE);

-- ConfigBus interface.
u_reg_gateway : cfgbus_register_wide
    generic map(
    DWIDTH      => cfg_word'length,
    DEVADDR     => DEVADDR,
    REGADDR     => RT_ADDR_GATEWAY,
    RSTVAL      => CFG_RESET)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(1),
    sync_clk    => clk,
    sync_val    => cfg_word);

u_reg_port_shdn : cfgbus_readonly
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => RT_ADDR_PORT_SHDN)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(2),
    reg_val     => cfg_shutdown);

cfg_ack <= cfgbus_merge(cfg_acks);

-- Break out individual portions of the configuration word.
-- TODO: These settings are copied from the original router.
--       Keep everything? Are any required/forbidden by RFC1812?
block_lcl_bcast     <= cfg_word(85);
block_noip_all      <= cfg_word(84);
block_noip_bcast    <= cfg_word(83);
block_ipv4_mcast    <= cfg_word(82);
block_ipv4_bcast    <= cfg_word(81);
block_bad_dmac      <= cfg_word(80);
cfg_macaddr         <= cfg_word(79 downto 32);
cfg_ipaddr          <= cfg_word(31 downto 0);

end router2_gateway;
