--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Address Resolution Protocol (ARP) packet interface
--
-- This block handles byte-by-byte implementation of the Address Resolution
-- Protocol (IETF RFC 826) to implement Proxy-ARP (IETF RFC 1027).  The
-- input is a filtered byte stream containing specific ARP fields only
-- (see router_arp_parse); the output is a sequence of ARP response frames.
--
-- If incoming traffic includes an ARP request for the remote subnet, this
-- block responds with its own MAC address.  Subnet parameters are adjustable
-- at runtime, corresponding to a narrow defined range (inner) or everything
-- outside that range (outer).
--
-- For convenience, the same block can provide ARP responses for the router's
-- IP address as well, if it's separate from the remote subnet.
--
-- TODO: Implement a proper TCAM search for multiple non-contiguous subnets.
--       This is OK for "home-router" setups with a single uplink, but doesn't
--       allow for more complex networks or multi-hop static routes.  For now,
--       a decent workaround is to instantiate multiple ARP-Proxy blocks.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;

entity router_arp_proxy is
    generic (
    -- Match a narrow subnet (inner) or everything else (outer)?
    SUBNET_INNER    : boolean;
    -- Set the MAC-address for the local interface.
    LOCAL_MACADDR   : mac_addr_t;
    -- Options for each output frame.
    ARP_APPEND_FCS  : boolean := false;
    MIN_FRAME_BYTES : natural := 0);
    port (
    -- Filtered receive interface
    arp_rx_data     : in  byte_t;
    arp_rx_first    : in  std_logic;
    arp_rx_last     : in  std_logic;
    arp_rx_write    : in  std_logic;

    -- Network transmit interface
    pkt_tx_data     : out byte_t;
    pkt_tx_last     : out std_logic;
    pkt_tx_valid    : out std_logic;
    pkt_tx_ready    : in  std_logic;

    -- Address configuration for the router (optional)
    router_addr     : in  ip_addr_t := IP_NOT_VALID;

    -- Subnet configuration for Proxy-ARP.
    -- TODO: Multiple subnets or a TCAM table?
    subnet_addr     : in  ip_addr_t;    -- e.g., 192.168.1.x
    subnet_mask     : in  ip_addr_t;    -- e.g., 255.255.255.0

    -- System clock and reset.
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end router_arp_proxy;

architecture router_arp_proxy of router_arp_proxy is

-- How many bytes in each ARP response? (Exclude CRC)
-- Minimum is 14 header + 28 ARP = 42 bytes.
function get_arplen return integer is
begin
    return int_max(42, MIN_FRAME_BYTES-4);
end function;
constant ARP_FRAME_BYTES : integer := get_arplen;

-- Parse useful fields from the input stream.
signal parse_commit : std_logic := '0';
signal parse_ignore : std_logic := '0';
signal parse_sha    : mac_addr_t := (others => '0');
signal parse_spa    : ip_addr_t := (others => '0');
signal parse_tpa    : ip_addr_t := (others => '0');

-- Construct each ARP response.
signal reply_state  : integer range 0 to ARP_FRAME_BYTES-1 := 0;
signal reply_data   : byte_t := (others => '0');
signal reply_last   : std_logic := '0';
signal reply_valid  : std_logic := '0';
signal reply_ready  : std_logic;

begin

-- Parse useful fields from the input stream.
p_parse : process(clk)
    variable rcvd_tpa     : ip_addr_t;
    variable match_opcode : std_logic := '0';
    variable match_router : std_logic := '0';
    variable match_subnet : std_logic := '0';
    variable sreg : std_logic_vector(159 downto 0) := (others => '0');
begin
    if rising_edge(clk) then
        -- Small state machine to ignore partial frames.
        -- (e.g., Had to discard the first part of a frame while busy.)
        if (reset_p = '1') then
            parse_ignore <= '0';    -- Ready to receive next frame
        elsif (arp_rx_write = '1' and reply_valid = '1') then
            parse_ignore <= '1';    -- Still busy, discard this frame
        elsif (arp_rx_write = '1' and arp_rx_first = '1') then
            parse_ignore <= '0';    -- Ready to receive next frame
        end if;

        -- Opcode must be ARP request (oldest byte = 0x01)
        match_opcode := bool2bit(sreg(159 downto 152) = x"01");

        -- Filter by TPA subnet (last four received bytes).
        rcvd_tpa := sreg(23 downto 0) & arp_rx_data;
        match_router := bool2bit(
            (router_addr = rcvd_tpa) and (router_addr /= IP_NOT_VALID));
        match_subnet := bool2bit(
            SUBNET_INNER xor ip_in_subnet(rcvd_tpa, subnet_addr, subnet_mask));

        -- Freeze the shift register is reply-builder is busy,
        -- otherwise update with each new received byte.
        if (arp_rx_write = '1' and reply_valid = '0') then
            sreg := sreg(151 downto 0) & arp_rx_data;
            parse_commit <= arp_rx_last and (not parse_ignore)
                        and match_opcode and (match_router or match_subnet);
        else
            parse_commit <= '0';
        end if;

        -- Fields of interest are pulled directly from the big shift register.
        parse_sha  <= sreg(159 downto 112);
        parse_spa  <= sreg(111 downto  80);
        parse_tpa  <= sreg( 31 downto   0);
    end if;
end process;

-- Construct each ARP response.
p_reply : process(clk)
    -- Fixed fields: EtherType, HTYPE, PTYPE, HLEN, PLEN, OPER
    constant ARP_FIXED_HDR : std_logic_vector(79 downto 0) :=
        x"0806_0001_0800_06_04_0002";
begin
    if rising_edge(clk) then
        -- Send each byte in the response frame:
        if (parse_commit = '1' or reply_ready = '1') then
            reply_last <= bool2bit(reply_state = ARP_FRAME_BYTES-1);
            if (reply_state < 6) then       -- Destination MAC
                reply_data <= get_byte_s(parse_sha, 5-reply_state);
            elsif (reply_state < 12) then   -- Source MAC
                reply_data <= get_byte_s(LOCAL_MACADDR, 11-reply_state);
            elsif (reply_state < 22) then   -- Fixed fields (see above)
                reply_data <= get_byte_s(ARP_FIXED_HDR, 21-reply_state);
            elsif (reply_state < 28) then   -- Response SHA = Our MAC
                reply_data <= get_byte_s(LOCAL_MACADDR, 27-reply_state);
            elsif (reply_state < 32) then   -- Response SPA = Request TPA
                reply_data <= get_byte_s(parse_tpa, 31-reply_state);
            elsif (reply_state < 38) then   -- Response THA = Request SHA
                reply_data <= get_byte_s(parse_sha, 37-reply_state);
            elsif (reply_state < 42) then   -- Response TPA = Request SPA
                reply_data <= get_byte_s(parse_spa, 41-reply_state);
            else                            -- Zero-pad (optional)
                reply_data <= (others => '0');
            end if;
        end if;

        -- Data-valid flag is set by the commit strobe, then held high
        -- until the next downstream block accepts the final byte.
        if (reset_p = '1') then
            reply_valid <= '0';
        elsif (parse_commit = '1') then
            reply_valid <= '1';
        elsif (reply_state = 0 and reply_ready = '1') then
            assert (reply_valid = '0' or reply_last = '1')
                report "Missing LAST strobe." severity error;
            reply_valid <= '0';
        end if;

        -- State counter is the byte offset for the NEXT byte to be sent.
        -- Increment it as soon as we've latched each value, above.
        if (reset_p = '1') then
            reply_state <= 0;       -- Reset to idle state.
        elsif ((parse_commit = '1') or (reply_state > 0 and reply_ready = '1')) then
            if (reply_state = ARP_FRAME_BYTES-1) then
                reply_state <= 0;   -- Done, revert to idle.
            else
                reply_state <= reply_state + 1;
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
        in_data     => reply_data,
        in_last     => reply_last,
        in_valid    => reply_valid,
        in_ready    => reply_ready,
        out_data    => pkt_tx_data,
        out_last    => pkt_tx_last,
        out_valid   => pkt_tx_valid,
        out_ready   => pkt_tx_ready,
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_nocrc : if not ARP_APPEND_FCS generate
    pkt_tx_data  <= reply_data;
    pkt_tx_last  <= reply_last;
    pkt_tx_valid <= reply_valid;
    reply_ready  <= pkt_tx_ready;
end generate;

end router_arp_proxy;
