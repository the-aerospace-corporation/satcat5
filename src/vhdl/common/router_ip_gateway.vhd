--------------------------------------------------------------------------
-- Copyright 2020-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Multipurpose IP-Gateway and ICMP server.
--
-- This block inspects IPv4 packets and handles various error conditions.
-- By default, it forwards IPv4 frames only, but it can be configured to
-- allow selective forwarding of raw-Ethernet frames.
--  * For IPv4 frames:
--      * Decrement the TTL field and update checksum accordingly.
--      * If the TTL countdown hits zero, drop frame and send an ICMP
--        "time exceeded" error message.
--      * Inspect the destination IP.
--          * If the destination is the router itself, handle accordingly:
--            Respond to specific ICMP requests:
--                (e.g., Echo request, Router solicitation, Timestamp)
--            Ignore all other ICMP requests.
--            All other protocols result in an ICMP error message.
--          * If the link is down, send an ICMP "unreachable" error.
--          * Otherwise, forward the packet as-is.
--  * For non-IPv4 frames, policy is set at build time.
--      * Always block non-IPv4 frames?
--      * Block or allow ARP frames? (EtherType = 0x0806)
--      * Block or allow broadcast destination MAC?
--
-- If an input frame is dropped for any reason, including rate-limiting
-- on an expected ICMP response, this block asserts the "in_drop" strobe.
-- This is not an error condition, but may be useful for diagnostics.
--
-- Since input and output are both Ethernet, they have the same MTU and
-- we do not need to support fragmentation changes.
--
-- The logic here is intended to fully comply with IETF RFC-1812,
-- "Requirements for IP Version 4 Routers", though the supported feature
-- set is extremely minimal.  Notable exceptions:
--  * No support for fragmentation or MTU limits.
--  * No support for LSR or SSR options.
--  * No support for SNMP.
--  * Maximum supported echo size is typically less than 576.
--
-- All input and output streams contain Ethernet frames with no FCS.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;

entity router_ip_gateway is
    generic (
    -- MAC address for the router itself
    ROUTER_MACADDR      : mac_addr_t;
    -- Rules for IPv4 packets
    IPV4_BLOCK_MCAST    : boolean := true;  -- Block IPv4 multicast?
    IPV4_BLOCK_FRAGMENT : boolean := true;  -- Block fragmented frames?
    IPV4_DMAC_FILTER    : boolean := true;  -- Destination MAC must be router?
    IPV4_DMAC_REPLACE   : boolean := true;  -- Replace destination MAC in output?
    IPV4_SMAC_REPLACE   : boolean := true;  -- Replace source MAC in output?
    -- Rules for non-IPv4 packets
    NOIP_BLOCK_ALL      : boolean := true;  -- Block all non-IP?
    NOIP_BLOCK_ARP      : boolean := true;  -- Block all ARP frames?
    NOIP_BLOCK_BCAST    : boolean := true;  -- Block non-IP broadcast?
    NOIP_DMAC_REPLACE   : boolean := true;  -- Replace destination MAC in output?
    NOIP_SMAC_REPLACE   : boolean := true;  -- Replace source MAC in output?
    -- ICMP buffer and ID parameters.
    ICMP_ECHO_BYTES     : natural := 64;
    ICMP_REPLY_TTL      : natural := 64;
    ICMP_ID_INIT        : natural := 0;
    ICMP_ID_INCR        : natural := 1;
    -- Enable diagnostic logging (sim only)
    DEBUG_VERBOSE       : boolean := false);
    port (
    -- Input stream (from source)
    in_data         : in  byte_t;
    in_last         : in  std_logic;
    in_valid        : in  std_logic;
    in_ready        : out std_logic;
    in_drop         : out std_logic;

    -- Main output stream (to destination)
    out_data        : out byte_t;
    out_last        : out std_logic;
    out_valid       : out std_logic;
    out_ready       : in  std_logic;

    -- ICMP command stream (back to source)
    icmp_data       : out byte_t;
    icmp_last       : out std_logic;
    icmp_valid      : out std_logic;
    icmp_ready      : in  std_logic;

    -- Router configuration
    router_ipaddr   : in  ip_addr_t;
    router_submask  : in  ip_addr_t;
    router_link_ok  : in  std_logic := '1';
    ipv4_dmac       : in  mac_addr_t := x"DEADBEEFCAFE";
    noip_dmac       : in  mac_addr_t := (others => '1');
    time_msec       : in  timestamp_t;

    -- System clock and reset.
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end router_ip_gateway;

architecture router_ip_gateway of router_ip_gateway is

-- Max header size = 36 bytes (14 Eth + 20 IP + 2 ICMP)
constant HEADER_BYTES   : integer := 36;

-- Shift register for the last six received bytes.
signal rx_write         : std_logic := '0';
signal rx_last          : std_logic := '0';
signal rx_data48        : std_logic_vector(47 downto 0);
signal rx_data32        : std_logic_vector(31 downto 0);
signal rx_data16        : std_logic_vector(15 downto 0);
signal rx_data08        : std_logic_vector( 7 downto 0);
signal rx_data08h       : std_logic_vector( 3 downto 0);
signal rx_data08l       : std_logic_vector( 3 downto 0);

-- Parse packet and decide if/how it should be forwarded.
signal parse_cmd        : action_t := ACT_DROP;
signal parse_done       : std_logic := '0';
signal parse_rdy        : std_logic := '0';
signal parse_bct        : integer range 0 to HEADER_BYTES := 0;
signal parse_len        : integer range 60 downto 0 := 0;
signal parse_rem        : integer range 59 downto 0 := 0;
signal parse_sum        : ip_checksum_t := (others => '0');
signal parse_ip_self    : std_logic := '0';
signal parse_ip_bcast   : std_logic := '0';
signal parse_chk_wrap   : std_logic := '0';
signal parse_dmac_bcast : std_logic := '0';
signal parse_dmac_mcast : std_logic := '0';
signal parse_dmac_self  : std_logic := '0';
signal parse_proto      : byte_t := (others => '0');
signal parse_ttl        : byte_u := (others => '0');

-- Synchronized queues for actions and frame data.
signal cmd_data         : action_t;
signal cmd_valid        : std_logic;
signal cmd_rd           : std_logic;
signal dat_data         : byte_t;
signal dat_last         : std_logic;
signal dat_valid        : std_logic;
signal dat_rd           : std_logic;

-- Modify the forwarded message:
signal fwd_bct          : integer range 0 to HEADER_BYTES := 0;
signal fwd_data         : byte_t := (others => '0');
signal fwd_last         : std_logic := '0';
signal fwd_write        : std_logic := '0';
signal fwd_hempty       : std_logic;

-- Report any dropped frames.
signal parse_drop       : std_logic := '0';
signal icmp_drop        : std_logic;

begin

-- Upstream flow control:
in_ready    <= fwd_hempty;

-- Top-level packet-dropped strobe:
in_drop     <= parse_drop or icmp_drop;

-- Shift register for the last six received bytes.
-- (Also generate truncated copies for cleaner syntax below.)
rx_data32   <= rx_data48(31 downto 0);
rx_data16   <= rx_data48(15 downto 0);
rx_data08   <= rx_data48( 7 downto 0);
rx_data08h  <= rx_data48( 7 downto 4);
rx_data08l  <= rx_data48( 3 downto 0);

p_sreg : process(clk)
begin
    if rising_edge(clk) then
        if (in_valid = '1' and fwd_hempty = '1') then
            rx_data48 <= rx_data48(39 downto 0) & in_data;
        end if;
        rx_last  <= in_valid and fwd_hempty and in_last;
        rx_write <= in_valid and fwd_hempty;
    end if;
end process;

-- Parse packet and decide if/how it should be forwarded.
-- Note: Max delay on a decision is end of Eth+IP header = 34 bytes.
p_parse : process(clk)
    procedure print_if_verbose(x : string) is
    begin
        if (DEBUG_VERBOSE and rx_write = '1' and parse_done = '0') then
            report x severity note;
        end if;
    end procedure;

    variable cmd : action_t := (others => 'X'); -- Don't-care
    variable rdy : std_logic := 'X';            -- Don't-care
begin
    if rising_edge(clk) then
        -- Decide the fate of this packet.
        cmd := (others => 'X');         -- Don't care
        rdy := '0';                     -- Default = no-change
        if (parse_bct = 5) then         -- Destination MAC (6 bytes)
            if (mac_is_swcontrol(rx_data48) or
                mac_is_l2multicast(rx_data48)) then
                cmd := ACT_DROP;        -- Block (illegal destination)
                rdy := rx_write;
                print_if_verbose("DROP: Illegal destination MAC");
            end if;
        elsif (parse_bct = 11) then        -- Source MAC (6 bytes)
            if (mac_is_broadcast(rx_data48) or
                mac_is_l2multicast(rx_data48) or
                mac_is_l3multicast(rx_data48)) then
                cmd := ACT_DROP;        -- Block (Illegal source)
                rdy := rx_write;
                print_if_verbose("DROP: Illegal source MAC");
            end if;
        elsif (parse_bct = 13) then     -- EtherType (2 bytes)
            if (rx_data16 = x"0800") then
                null;                   -- Decide later (IPv4)
            elsif (NOIP_BLOCK_ALL) then
                cmd := ACT_DROP;        -- Blocked (Non-IPv4)
                rdy := rx_write;
                print_if_verbose("DROP: Non-IPv4 blocked");
            elsif (NOIP_BLOCK_ARP and rx_data16 = x"0806") then
                cmd := ACT_DROP;        -- Blocked (ARP)
                rdy := rx_write;
                print_if_verbose("DROP: ARP blocked");
            elsif (NOIP_BLOCK_BCAST and parse_dmac_bcast = '1') then
                cmd := ACT_DROP;        -- Blocked (MAC-Broadcast)
                rdy := rx_write;
                print_if_verbose("DROP: Broadcast MAC");
            else
                cmd := ACT_FWD_RAW;     -- Forward raw packet!
                rdy := rx_write;
                print_if_verbose("FWD: Raw Ethernet");
            end if;
        elsif (parse_bct = 14) then     -- IP version/IHL
            if (rx_data08h /= x"4") then
                cmd := ACT_DROP;        -- Unsupported IP version
                rdy := rx_write;
                print_if_verbose("DROP: Unsupported IP version");
            elsif (u2i(rx_data08l) < 5) then
                cmd := ACT_DROP;        -- Invalid IP header length
                rdy := rx_write;
                print_if_verbose("DROP: Invalid IHL");
            end if;
        elsif (parse_bct = 17) then     -- Total length
            if (unsigned(rx_data16) < parse_len) then
                cmd := ACT_DROP;        -- Total length less than IHL
                rdy := rx_write;
                print_if_verbose("DROP: Invalid TLEN");
            end if;
        elsif (parse_bct = 21) then     -- Fragmentation flags
            if (IPV4_BLOCK_FRAGMENT and rx_data16 /= x"4000" and rx_data16 /= x"0000") then
                cmd := ACT_DROP;        -- MF set, or fragment offset > 0
                rdy := rx_write;        -- (User build-time policy)
                print_if_verbose("DROP: IP fragment");
            end if;
        elsif (parse_bct = 29) then     -- Source IP (4 bytes)
            if (ip_is_broadcast(rx_data32) or
                ip_is_multicast(rx_data32) or
                ip_is_reserved(rx_data32) or
                router_ipaddr = rx_data32) then
                cmd := ACT_DROP;        -- Blocked (Illegal source)
                rdy := rx_write;
                print_if_verbose("DROP: Illegal source IP");
            end if;
        elsif (parse_bct = 33) then     -- Destination IP (4 bytes)
            if (ip_is_reserved(rx_data32)) then
                cmd := ACT_DROP;        -- Blocked (reserved address)
                rdy := rx_write;        -- (RFC 1812 section 4.2.3.1)
                print_if_verbose("DROP: Reserved IP");
            elsif (ip_is_broadcast(rx_data32)) then
                null;                   -- Limited-broadcast handled below.
            elsif (IPV4_BLOCK_MCAST and ip_is_multicast(rx_data32)) then
                cmd := ACT_DROP;        -- Blocked (multicast)
                rdy := rx_write;        -- (User build-time policy)
                print_if_verbose("DROP: Multicast IP");
            elsif (parse_dmac_bcast = '1' and not ip_is_multicast(rx_data32)) then
                cmd := ACT_DROP;        -- Blocked (Illegal MAC broadcast)
                rdy := rx_write;        -- (RFC 1812 section 4.2.3.1)
                print_if_verbose("DROP: MAC bcast must be IP mcast");
            elsif (parse_dmac_mcast = '1' and not ip_is_multicast(rx_data32)) then
                cmd := ACT_DROP;        -- Blocked (Illegal MAC multicast)
                rdy := rx_write;        -- (RFC 1812 section 4.2.3.1)
                print_if_verbose("DROP: MAC mcast must be IP mcast");
            elsif (IPV4_DMAC_FILTER and parse_dmac_self = '0') then
                cmd := ACT_DROP;        -- Blocked (Not sent to router)
                rdy := rx_write;        -- (User build-time policy)
                print_if_verbose("DROP: MAC dst is not router");
            end if;
        elsif (parse_bct = 34 and parse_rem = 0) then   -- End of IP header
            if (parse_sum /= x"FFFF") then
                cmd := ACT_DROP;        -- Dropped (Bad checksum)
                rdy := rx_write;
                print_if_verbose("DROP: Bad IP checksum");
            elsif (parse_ip_self = '0' and router_link_ok = '0') then
                cmd := ACT_ICMP_DNU;    -- Destination network unreachable
                rdy := rx_write;
                print_if_verbose("ICMP: Destination network unreachable");
            elsif (parse_ip_self = '0' and parse_ttl = 0) then
                -- RFC-1812 Section 4.2.2.9: Only check TTL if forwarding.
                cmd := ACT_ICMP_TTL;    -- TTL / Hop limit exceeded
                rdy := rx_write;
                print_if_verbose("ICMP: Time exceeded");
            elsif (parse_ip_self = '0' and parse_chk_wrap = '0') then
                cmd := ACT_FWD_IP0;     -- Forward IPv4 packet! (No carry)
                rdy := rx_write;
                print_if_verbose("FWD: IP packet");
            elsif (parse_ip_self = '0') then
                cmd := ACT_FWD_IP1;     -- Forward IPv4 packet! (With carry)
                rdy := rx_write;
                print_if_verbose("FWD: IP packet");
            elsif ((parse_ip_bcast = '0') and (parse_proto = x"06" or parse_proto = x"11")) then
                cmd := ACT_ICMP_DPU;    -- Destination port unreachable
                rdy := rx_write;        -- (Recommended for TCP/UDP ping)
                print_if_verbose("ICMP: Destination port unreachable");
            elsif (parse_ip_bcast = '0' and parse_proto /= x"01") then
                cmd := ACT_ICMP_DRU;    -- Destination protocol unreachable
                rdy := rx_write;        -- (This router only speaks ICMP)
                print_if_verbose("ICMP: Destination protocol unreachable");
            end if;
        elsif (parse_bct = 35) then     -- Type + opcode from ICMP header
            case rx_data16 is
                when x"0800" => cmd := ACT_ICMP_ECHO;   -- Echo request
                                print_if_verbose("ICMP: Echo request");
                when x"0D00" => cmd := ACT_ICMP_TIME;   -- Timestamp request
                                print_if_verbose("ICMP: Timestamp request");
                when x"1100" => cmd := ACT_ICMP_MASK;   -- Address mask request
                                print_if_verbose("ICMP: Address mask request");
                when others  => cmd := ACT_DROP;        -- Unsupported opcode
                                print_if_verbose("DROP: Unsupported ICMP");
            end case;
            rdy := rx_write;
        end if;

        -- Update the IP-header length countdown.
        if (reset_p = '1' or rx_last = '1') then
            parse_len <= 0;
            parse_rem <= 0;
        elsif (parse_bct = 14 and rx_write = '1' and rx_data08l /= x"0") then
            parse_len <= 4*u2i(rx_data08l);
            parse_rem <= 4*u2i(rx_data08l) - 1;
        elsif (rx_write = '1' and parse_rem > 0) then
            parse_rem <= parse_rem - 1;
        end if;

        -- Update the IP-header running checksum.
        -- (Refer to IETF RFC 1071 for details.)
        if (reset_p = '1') then
            parse_sum <= (others => '0');
        elsif (rx_write = '1' and parse_rem = 0) then
            parse_sum <= (others => '0');
        elsif (rx_write = '1' and parse_rem mod 2 = 1) then
            parse_sum <= ip_checksum(parse_sum, unsigned(rx_data16));
        end if;

        -- Latch the "TTL" and "protocol" fields for later use.
        if (parse_bct = 22 and rx_write = '1') then
            parse_ttl <= unsigned(rx_data08);
        end if;

        if (parse_bct = 23 and rx_write = '1') then
            parse_proto <= rx_data08;
        end if;

        -- Will the 2nd byte of checksum wrap around when incremented?
        if (parse_bct = 25 and rx_write = '1') then
            parse_chk_wrap <= bool2bit(rx_data08 = x"FF");
        end if;

        -- Is a given IP packet addressed to the router?
        -- (Note this includes "limited broadcasts" to 255.255.255.255.)
        if (parse_bct = 33 and rx_write = '1') then
            parse_ip_self   <= bool2bit(rx_data32 = router_ipaddr or rx_data32 = IP_BROADCAST);
            parse_ip_bcast  <= bool2bit(ip_is_broadcast(rx_data32));
        end if;

        -- Destination-MAC matching.
        if (parse_bct = 5 and rx_write = '1') then
            parse_dmac_bcast    <= bool2bit(mac_is_broadcast(rx_data48));
            parse_dmac_mcast    <= bool2bit(mac_is_l3multicast(rx_data48));
            parse_dmac_self     <= bool2bit(rx_data48 = ROUTER_MACADDR)
                                or bool2bit(rx_data48 = MAC_ADDR_BROADCAST);
        end if;

        -- Drive "rdy" strobe when we decide the packet's fate.
        -- Hold "done" flag until start of next packet, to prevent changes.
        if (reset_p = '1' or parse_bct = 0) then
            parse_cmd   <= ACT_DROP;
            parse_rdy   <= '0';
            parse_drop  <= '0';
            parse_done  <= '0';
        elsif (parse_done = '0' and rdy = '1') then
            parse_cmd   <= cmd;
            parse_rdy   <= '1';
            parse_drop  <= bool2bit(cmd = ACT_DROP);
            parse_done  <= '1';
        else
            parse_rdy   <= '0';
            parse_drop  <= '0';
        end if;

        -- Increment the byte-offset counter.
        --  0-13 = Ethernet header
        -- 14-33 = IP header (ignore all options)
        -- 34-35 = ICMP header (if applicable)
        if (reset_p = '1') then
            parse_bct <= 0;     -- Global reset
        elsif (rx_last = '1') then
            parse_bct <= 0;     -- Start of new frame
        elsif (rx_write = '1' and parse_bct < 34) then
            -- Increment up to end of the basic IP header (first 20 bytes)
            parse_bct <= parse_bct + 1;
        elsif (rx_write = '1' and parse_rem = 0 and parse_bct < HEADER_BYTES) then
            -- Stop if there are extra options, then continue with ICMP header.
            parse_bct <= parse_bct + 1;
        end if;
    end if;
end process;

-- Synchronized queues for actions and frame data.
-- Data buffer must be deep enough to accommodate maximum decision delay,
-- which is set by the maximum Ethernet + IPv4 header length (i.e., 74 bytes).
-- Command buffer just needs a few words to handle mixed long/short frames.
cmd_rd <= dat_rd and dat_last;
dat_rd <= cmd_valid and dat_valid and fwd_hempty;

u_fifo_cmd : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => ACT_WIDTH,
    DEPTH_LOG2  => 3)   -- 2^3 = 8 words
    port map(
    in_data     => parse_cmd,
    in_write    => parse_rdy,
    out_data    => cmd_data,
    out_valid   => cmd_valid,
    out_read    => cmd_rd,
    clk         => clk,
    reset_p     => reset_p);

u_fifo_dat : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8,   -- 8-bit datapath
    DEPTH_LOG2  => 7)   -- 2^7 = 128 bytes
    port map(
    in_data     => rx_data08,
    in_last     => rx_last,
    in_write    => rx_write,
    out_data    => dat_data,
    out_last    => dat_last,
    out_valid   => dat_valid,
    out_read    => dat_rd,
    clk         => clk,
    reset_p     => reset_p);

-- Generate ICMP reply messages.
-- (Note: Construction of the reply requires us to forward the first N
--        bytes of the sender's message, for identification purposes.)
u_icmp : entity work.router_icmp_send
    generic map(
    ROUTER_MAC  => ROUTER_MACADDR,
    ICMP_TTL    => ICMP_REPLY_TTL,
    IP_ID_INIT  => ICMP_ID_INIT,
    IP_ID_INCR  => ICMP_ID_INCR,
    ECHO_BYTES  => ICMP_ECHO_BYTES)
    port map(
    in_cmd      => cmd_data,
    in_data     => dat_data,
    in_last     => dat_last,
    in_write    => dat_rd,
    icmp_data   => icmp_data,
    icmp_last   => icmp_last,
    icmp_valid  => icmp_valid,
    icmp_ready  => icmp_ready,
    icmp_drop   => icmp_drop,
    router_ip   => router_ipaddr,
    subnet_mask => router_submask,
    time_msec   => time_msec,
    clk         => clk,
    reset_p     => reset_p);

-- Modify the forwarded message:
p_fwd : process(clk)
    variable dbl_carry : std_logic := '0';
begin
    if rising_edge(clk) then
        if (cmd_data = ACT_FWD_IP0 or cmd_data = ACT_FWD_IP1) then
            -- IPv4 frames modify selected fields:
            if (IPV4_DMAC_REPLACE and fwd_bct < 6) then
                -- If enabled, replace destination-MAC with a placeholder address.
                -- Do NOT use the broadcast address per RFC 1812 section 4.2.3.1,
                -- which requires that such packets be blocked by the next router.
                fwd_data <= get_byte_s(ipv4_dmac, 5-fwd_bct);
            elsif (IPV4_SMAC_REPLACE and 6 <= fwd_bct and fwd_bct < 12) then
                -- If enabled, replace source-MAC with the router's address.
                fwd_data <= get_byte_s(ROUTER_MACADDR, 11-fwd_bct);
            elsif (fwd_bct = 22) then
                -- Decrement the TTL field.
                fwd_data <= std_logic_vector(unsigned(dat_data) - 1);
            elsif (fwd_bct = 24) then
                -- Increment first byte of the checksum.
                -- (TTL field is in the MSBs of the 16-bit checksum.)
                if (dat_data = x"FE" and cmd_data = ACT_FWD_IP1) then
                    fwd_data <= x"00";  -- Edge case from RFC 1624.
                elsif (dat_data = x"FF" and cmd_data = ACT_FWD_IP1) then
                    fwd_data <= x"01";  -- Double-overflow case.
                else
                    fwd_data <= std_logic_vector(unsigned(dat_data) + 1);
                end if;
            elsif (fwd_bct = 25 and dbl_carry = '1') then
                -- Increment second byte of the checksum (if applicable)
                fwd_data <= std_logic_vector(unsigned(dat_data) + 1);
            else
                -- All other fields forwarded as-is.
                fwd_data <= dat_data;
            end if;
        else
            -- Separate modification rules for Raw-Ethernet frames:
            if (NOIP_DMAC_REPLACE and fwd_bct < 6) then
                -- If enabled, replace destination-MAC with the designated fixed address.
                fwd_data <= get_byte_s(noip_dmac, 5-fwd_bct);
            elsif (NOIP_SMAC_REPLACE and 6 <= fwd_bct and fwd_bct < 12) then
                -- If enabled, replace source-MAC with the router's address.
                fwd_data <= get_byte_s(ROUTER_MACADDR, 11-fwd_bct);
            else
                -- All other fields forwarded as-is.
                fwd_data <= dat_data;
            end if;
        end if;

        -- Drive the "last" and "write" strobes.
        if (cmd_data = ACT_FWD_RAW and not NOIP_BLOCK_ALL) then
            fwd_last    <= dat_last;
            fwd_write   <= dat_rd;
        elsif (cmd_data = ACT_FWD_IP0 or cmd_data = ACT_FWD_IP1) then
            fwd_last    <= dat_last;
            fwd_write   <= dat_rd;
        else
            fwd_last    <= '0';
            fwd_write   <= '0';
        end if;

        -- Flag indicating when to increment the second checksum byte.
        -- We use the method in IETF RFC-1141, with correction for the edge
        -- case discussed in RFC-1624, when the final sum would be 0xFFFF.
        if (dat_rd = '1' and fwd_bct = 24) then
            dbl_carry := bool2bit(dat_data = x"FE" and cmd_data = ACT_FWD_IP1)
                      or bool2bit(dat_data = x"FF");
        end if;

        -- Update the byte offset counter.
        if (reset_p = '1' or cmd_rd = '1') then
            fwd_bct <= 0;
        elsif (dat_rd = '1' and fwd_bct < HEADER_BYTES) then
            fwd_bct <= fwd_bct + 1;
        end if;
    end if;
end process;

-- Output FIFO for downstream flow-control.
u_fifo_out : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8,
    DEPTH_LOG2  => 4)
    port map(
    in_data     => fwd_data,
    in_last     => fwd_last,
    in_write    => fwd_write,
    fifo_hempty => fwd_hempty,
    out_data    => out_data,
    out_last    => out_last,
    out_valid   => out_valid,
    out_read    => out_ready,
    clk         => clk,
    reset_p     => reset_p);

end router_ip_gateway;
