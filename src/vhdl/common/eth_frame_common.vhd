--------------------------------------------------------------------------
-- Copyright 2019-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Package definition: Useful constants and functions for Ethernet frames
--
-- This package define a variety constants and functions for manipulating
-- Ethernet frames, to maximize code reuse among various blocks.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package eth_frame_common is
    -- Define SLV and UNSIGNED "byte" types.
    subtype byte_t is std_logic_vector(7 downto 0);
    subtype byte_u is unsigned(7 downto 0);
    subtype nybb_t is std_logic_vector(3 downto 0);
    subtype nybb_u is unsigned(3 downto 0);

    -- Size parameters including header, user data, and FCS.
    constant HEADER_CRC_BYTES   : integer := 18;    -- Header and CRC bytes ONLY.
    constant HEADER_TAG_BYTES   : integer := 4;     -- Additional bytes for 802.11Q
    constant MIN_RUNT_BYTES     : integer := 18;    -- Minimum runt frame
    constant MIN_FRAME_BYTES    : integer := 64;    -- Minimum normal frame
    constant MAX_FRAME_BYTES    : integer := 1522;  -- Maximum normal frame
    constant MAX_JUMBO_BYTES    : integer := 9022;  -- Maximum jumbo frame

    -- Ethernet header: https://en.wikipedia.org/wiki/Ethernet_frame
    --  Bytes  0- 5 = Destination MAC
    --  Bytes  6-11 = Source MAC
    --  Bytes 12-13 = EtherType
    --  User data starts at byte 14.
    --  Last four bytes are FCS (CRC32), if present.
    constant ETH_HDR_DSTMAC     : integer := 0;
    constant ETH_HDR_SRCMAC     : integer := 6;
    constant ETH_HDR_ETYPE      : integer := 12;
    constant ETH_HDR_DATA       : integer := 14;

    -- Define byte-offsets for fields in a standard IP frame header.
    -- (Assume IP header is preceded by the 14-byte Ethernet header.)
    -- See also: https://en.wikipedia.org/wiki/IPv4#Header
    constant IP_HDR_VERSION     : integer := ETH_HDR_DATA + 0;  -- Version + IP Header length
    constant IP_HDR_DSCP_ECH    : integer := ETH_HDR_DATA + 1;  -- QoS and ECN flags
    constant IP_HDR_TOTAL_LEN   : integer := ETH_HDR_DATA + 2;  -- Length (hdr + contents)
    constant IP_HDR_IDCOUNT     : integer := ETH_HDR_DATA + 4;  -- Pkt ID (usually a counter)
    constant IP_HDR_FRAGMENT    : integer := ETH_HDR_DATA + 6;  -- Fragment flags and offset
    constant IP_HDR_TTL         : integer := ETH_HDR_DATA + 8;  -- Time-to-live counter
    constant IP_HDR_PROTOCOL    : integer := ETH_HDR_DATA + 9;  -- Protocol (ICMP/UDP/TCP/etc)
    constant IP_HDR_CHECKSUM    : integer := ETH_HDR_DATA + 10; -- Header checksum
    constant IP_HDR_SRCADDR     : integer := ETH_HDR_DATA + 12; -- Source address
    constant IP_HDR_DSTADDR     : integer := ETH_HDR_DATA + 16; -- Destination address
    constant IP_HDR_OPTIONS     : integer := ETH_HDR_DATA + 20; -- Optional field(s)
    constant IP_HDR_MAX         : integer := ETH_HDR_DATA + 60; -- Maximum end of IP header
    function IP_HDR_DATA(ihl : nybb_u) return integer;          -- Start of data field
    -- Note: Data starts after the variable-length OPTIONS field, provide
    --       IP-header length (IHL) field to determine the initial offset.

    -- Define byte-offsets for fields in the IPv4 + UDP frame header.
    -- (Assume IP header is preceded by the 14-byte Ethernet header.)
    -- See also: https://en.wikipedia.org/wiki/User_Datagram_Protocol#UDP_datagram_structure
    constant UDP_HDR_MAX        : integer := IP_HDR_MAX + 8;    -- Maximum end of UDP header
    function UDP_HDR_SRC(ihl : nybb_u) return integer;          -- Source port (U16)
    function UDP_HDR_DST(ihl : nybb_u) return integer;          -- Destination port (U16)
    function UDP_HDR_LEN(ihl : nybb_u) return integer;          -- Length field (U16)
    function UDP_HDR_CHK(ihl : nybb_u) return integer;          -- Checksum field (U16)
    function UDP_HDR_DAT(ihl : nybb_u) return integer;          -- Start of user data

    -- Byte or word counter for parsing Ethernet and IP headers.
    constant MAC_BCOUNT_MAX : integer := IP_HDR_MAX + 1;
    subtype mac_bcount_t is integer range 0 to MAC_BCOUNT_MAX;
    function mac_wcount_max(bwidth : positive) return mac_bcount_t;

    -- Internal 10 GbE data streams send up to 8 bytes per clock.  Byte order
    -- in all cases is big-endian (i.e., most significant byte first.)  Each
    -- word except the last must be completely filled; the last word of each
    -- frame is indicated when NLAST > 0.  The final word may contain 1-8
    -- bytes and must be left-justified (i.e., data in MSBs, padding in LSBs).
    -- For additional information, refer to "fifo_packet.vhd".
    subtype xword_t is std_logic_vector(63 downto 0);   -- Data word (SLV)
    subtype xword_u is std_logic_vector(63 downto 0);   -- Data word (Unsigned)
    subtype xlast_i is integer range 0 to 8;            -- NLAST indicator
    subtype xlast_v is std_logic_vector(3 downto 0);    -- Alternate form

    function xlast_v2i(x : xlast_v) return xlast_i;
    function xlast_i2v(x : xlast_i) return xlast_v;

    -- Local type definitions for Frame Check Sequence (FCS):
    subtype crc_word_t is std_logic_vector(31 downto 0);
    type byte_array_t is array(natural range <>) of byte_t;
    constant CRC_INIT    : crc_word_t := (others => '1');
    constant CRC_RESIDUE : crc_word_t := x"C704DD7B";
    constant FCS_BYTES   : integer := 4;

    -- Type definitions for common Ethernet header fields:
    constant MAC_ADDR_WIDTH : integer := 48;
    constant MAC_TYPE_WIDTH : integer := 16;
    subtype mac_addr_t is std_logic_vector(MAC_ADDR_WIDTH-1 downto 0);
    subtype mac_type_t is std_logic_vector(MAC_TYPE_WIDTH-1 downto 0);
    constant MAC_ADDR_BROADCAST : mac_addr_t := (others => '1');

    -- Functions for checking special MAC addresses:
    function mac_is_swcontrol(mac : mac_addr_t) return boolean;
    function mac_is_l2multicast(mac : mac_addr_t) return boolean;
    function mac_is_l3multicast(mac : mac_addr_t) return boolean;
    function mac_is_broadcast(mac : mac_addr_t) return boolean;

    -- Define well-known EtherTypes:
    constant ETYPE_IPV4 : mac_type_t := x"0800";    -- Internet Protocol, Version 4
    constant ETYPE_ARP  : mac_type_t := x"0806";    -- Address Resolution Protocol
    constant ETYPE_VLAN : mac_type_t := x"8100";    -- 802.1Q VLAN tags (C-VLAN)
    constant ETYPE_VSVC : mac_type_t := x"88A8";    -- 802.1Q VLAN tags (S-VLAN)
    constant ETYPE_PTP  : mac_type_t := x"88F7";    -- Precision Time Protocol

    -- Well-known IPv4 protocols (IP_HDR_PROTOCOL):
    constant IPPROTO_ICMP   : byte_t := x"01";      -- Internet Control Message Protocol
    constant IPPROTO_IGMP   : byte_t := x"02";      -- Internet Group Management Protocol
    constant IPPROTO_TCP    : byte_t := x"06";      -- Transmission Control Protocol
    constant IPPROTO_UDP    : byte_t := x"11";      -- User Datagram Protocol

    -- Type definitions for 802.1Q tags:
    constant VLAN_HDR_WIDTH : integer := 16;
    constant VLAN_VID_WIDTH : integer := 12;
    subtype vlan_hdr_t is std_logic_vector(15 downto 0);
    subtype vlan_pcp_t is unsigned(2 downto 0);     -- Priority code point (PCP)
    subtype vlan_dei_t is std_logic;                -- Drop-eligible indicator (DEI)
    subtype vlan_vid_t is unsigned(11 downto 0);    -- VLAN identifier (VID)
    constant PCP_NONE   : vlan_pcp_t := "000";      -- Default priority (zero)
    constant DEI_NONE   : vlan_dei_t := '0';        -- Default DEI (not set)
    constant VID_NONE   : vlan_vid_t := x"000";     -- Null or unspecified VID
    constant VID_RSVD   : vlan_vid_t := x"FFF";     -- Reserved VID (illegal)
    constant VHDR_NONE  : vlan_hdr_t := x"0000";    -- Null or unspecified tag

    -- Extract fields from the VLAN header (Tag Control Information = TCI)
    function vlan_get_pcp(hdr : vlan_hdr_t) return vlan_pcp_t;
    function vlan_get_dei(hdr : vlan_hdr_t) return vlan_dei_t;
    function vlan_get_vid(hdr : vlan_hdr_t) return vlan_vid_t;
    function vlan_get_hdr(
        pcp: vlan_pcp_t;
        dei: vlan_dei_t;
        vid: vlan_vid_t)
        return vlan_hdr_t;

    -- Type definitions for setting per-port VLAN tag policy.
    -- (These correspond to the modes defined in 802.1Q Section 6.9.)
    subtype tag_policy_t is std_logic_vector(1 downto 0);
    constant VTAG_ADMIT_ALL : tag_policy_t := "00"; -- Admit all frames (default)
    constant VTAG_PRIORITY  : tag_policy_t := "01"; -- Admit only untagged and priority-tagged frames
    constant VTAG_MANDATORY : tag_policy_t := "10"; -- Admit only VLAN-tagged frames
    constant VTAG_RESERVED  : tag_policy_t := "11"; -- Reserved / undefined

    -- Ethernet preamble definitions.
    constant ETH_AMBLE_PRE  : byte_t := x"55";  -- 7-byte preamble
    constant ETH_AMBLE_SOF  : byte_t := x"D5";  -- Start-of-frame marker

    -- SLIP token definitions.
    constant SLIP_FEND      : byte_t := X"C0";  -- End-of-frame marker
    constant SLIP_ESC       : byte_t := X"DB";  -- Escape marker
    constant SLIP_ESC_END   : byte_t := X"DC";  -- Escaped FEND
    constant SLIP_ESC_ESC   : byte_t := X"DD";  -- Escaped ESC

    -- Utility functions for determining if a given byte is currently
    -- present in an arbitrary-width data stream, then extracting it.
    function strm_byte_present(
        bwidth  : positive;         -- Bytes per clock
        bidx    : natural;          -- Byte index of interest
        wcount  : natural)          -- Rcvd word count (0 = start-of-frame)
        return boolean;
    function strm_byte_value(
        bwidth  : positive;         -- Bytes per clock
        bidx    : natural;          -- Byte index of interest
        data    : std_logic_vector) -- Input vector (width = 8*bwidth)
        return byte_t;
    function strm_byte_value(
        bidx    : natural;          -- Byte index of interest
        data    : std_logic_vector) -- Input vector (width = arbitrary)
        return byte_t;

    -- Flip bit-order of the given byte, or each byte in a word.
    function flip_byte(data : byte_t) return byte_t;
    function flip_word(data : crc_word_t) return crc_word_t;
    function flip_bits_each_byte(data : crc_word_t) return crc_word_t;

    -- Flip byte-order of the given word (little-endian <-> big-endian).
    function endian_swap(data : crc_word_t) return crc_word_t;

    -- Byte-at-a-time CRC32 update function for polynomial 0x04C11DB7
    -- Derived from general-purpose CRC32 by Michael Cheung, 2014 June.
    function crc_next(prev : crc_word_t; data : byte_t) return crc_word_t;
end package;


library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package body eth_frame_common is

function IP_HDR_DATA(ihl : nybb_u) return integer is
begin
    return IP_HDR_VERSION + 4 * to_integer(ihl);
end function;

function UDP_HDR_SRC(ihl : nybb_u) return integer is
begin
    return IP_HDR_DATA(ihl) + 0;
end function;

function UDP_HDR_DST(ihl : nybb_u) return integer is
begin
    return IP_HDR_DATA(ihl) + 2;
end function;

function UDP_HDR_LEN(ihl : nybb_u) return integer is
begin
    return IP_HDR_DATA(ihl) + 4;
end function;

function UDP_HDR_CHK(ihl : nybb_u) return integer is
begin
    return IP_HDR_DATA(ihl) + 6;
end function;

function UDP_HDR_DAT(ihl : nybb_u) return integer is
begin
    return IP_HDR_DATA(ihl) + 8;
end function;

function mac_is_swcontrol(mac : mac_addr_t) return boolean is
    constant lsb : byte_u := unsigned(mac(7 downto 0));
begin
    -- Reserved MAC addresses 01:80:C2:00:00:00 through :0F
    -- (Used for PAUSE frames, Spanning Tree Protocol, etc.)
    return (mac(47 downto 8) = x"0180C20000") and (lsb < 16);
end function;

function mac_is_l2multicast(mac : mac_addr_t) return boolean is
begin
    return (mac(47 downto 24) = x"0180C2")  -- Multicast MAC (01:80:C2:*:*:*)
       and (not mac_is_swcontrol(mac));     -- ...except :00 through :0F
end function;

function mac_is_l3multicast(mac : mac_addr_t) return boolean is
begin
    return (mac(47 downto 24) = x"01005E"); -- IPv4 Multicast (01:00:5E:*:*:*)
end function;

function mac_is_broadcast(mac : mac_addr_t) return boolean is
begin
    return (mac = MAC_ADDR_BROADCAST);      -- Broadcast MAC (FF:FF:FF:FF:FF:FF)
end function;

function mac_wcount_max(bwidth : positive) return mac_bcount_t is
begin
    -- Return index of the word just after the last possible header byte.
    return 1 + (IP_HDR_MAX / bwidth);
end function;

function xlast_v2i(x : xlast_v) return xlast_i is
    constant XMAX : integer := 8;
    variable xi : integer range 0 to 15 := to_integer(unsigned(x));
begin
    if (xi < XMAX) then
        return xi;
    else
        return XMAX;
    end if;
end function;

function xlast_i2v(x : xlast_i) return xlast_v is
begin
    return std_logic_vector(to_unsigned(x, 4));
end function;

function vlan_get_pcp(hdr : vlan_hdr_t) return vlan_pcp_t is
    variable pcp : vlan_pcp_t := unsigned(hdr(15 downto 13));
begin
    return pcp;     -- Priority Code Point = Bits 15-13
end function;

function vlan_get_dei(hdr : vlan_hdr_t) return vlan_dei_t is
begin
    return hdr(12); -- Drop Eligible Indicator = Bit 12
end function;

function vlan_get_vid(hdr : vlan_hdr_t) return vlan_vid_t is
    variable vid : vlan_vid_t := unsigned(hdr(11 downto 0));
begin
    return vid;     -- Virtual LAN Identifier = Bits 11-0
end function;

function vlan_get_hdr(
    pcp: vlan_pcp_t;
    dei: vlan_dei_t;
    vid: vlan_vid_t)
    return vlan_hdr_t
is
    variable hdr : vlan_hdr_t :=
        std_logic_vector(pcp) & dei & std_logic_vector(vid);
begin
    return hdr;
end function;

function strm_byte_present(
    bwidth  : positive;
    bidx    : natural;
    wcount  : natural)
    return boolean
is
    constant widx : natural := bidx / bwidth;   -- Round down
begin
    return (wcount = widx);
end function;

function strm_byte_value(
    bwidth  : positive;
    bidx    : natural;
    data    : std_logic_vector)
    return byte_t
is
    constant bleft  : positive := data'left - 8 * (bidx mod bwidth);
    variable result : byte_t := data(bleft downto bleft-7);
begin
    assert (data'length = 8 * bwidth);
    return result;
end function;

function strm_byte_value(
    bidx    : natural;
    data    : std_logic_vector)
    return byte_t
is
    constant bwidth : positive := data'length / 8;
    constant bleft  : positive := data'left - 8 * (bidx mod bwidth);
    variable result : byte_t := data(bleft downto bleft-7);
begin
    assert (data'length = 8 * bwidth);
    return result;
end function;

function flip_byte(data : byte_t) return byte_t is
    variable drev : byte_t;
begin
    for i in drev'range loop
        drev(i) := data(7-i);
    end loop;
    return drev;
end function;

function flip_word(data : crc_word_t) return crc_word_t is
    variable drev : crc_word_t;
begin
    for i in drev'range loop
        drev(i) := data(31-i);
    end loop;
    return drev;
end function;

function flip_bits_each_byte(data : crc_word_t) return crc_word_t is
    constant drev : crc_word_t :=
        flip_byte(data(31 downto 24)) &
        flip_byte(data(23 downto 16)) &
        flip_byte(data(15 downto 8)) &
        flip_byte(data(7 downto 0));
begin
    return drev;
end function;

function endian_swap(data : crc_word_t) return crc_word_t is
    constant drev : crc_word_t :=
        data(7 downto 0) & data(15 downto 8) & data(23 downto 16) & data(31 downto 24);
begin
    return drev;
end function;

function crc_next(prev : crc_word_t; data : byte_t) return crc_word_t is
    variable drev   : byte_t;
    variable result : crc_word_t;
begin
    -- Reverse input bit order.
    -- (Ethernet convention is LSB-first, with CRC sent MSB-first)
    drev := flip_byte(data);

    -- Giant XOR table for the specified polynomial.
    result(0)  := drev(6) xor drev(0) xor prev(24) xor prev(30);
    result(1)  := drev(7) xor drev(6) xor drev(1) xor drev(0) xor prev(24) xor prev(25) xor prev(30) xor prev(31);
    result(2)  := drev(7) xor drev(6) xor drev(2) xor drev(1) xor drev(0) xor prev(24) xor prev(25) xor prev(26) xor prev(30) xor prev(31);
    result(3)  := drev(7) xor drev(3) xor drev(2) xor drev(1) xor  prev(25) xor prev(26) xor prev(27) xor prev(31);
    result(4)  := drev(6) xor drev(4) xor drev(3) xor drev(2) xor drev(0) xor prev(24) xor prev(26) xor prev(27) xor prev(28) xor prev(30);
    result(5)  := drev(7) xor drev(6) xor drev(5) xor drev(4) xor drev(3) xor drev(1) xor drev(0) xor prev(24) xor prev(25) xor prev(27) xor prev(28) xor prev(29) xor prev(30) xor prev(31);
    result(6)  := drev(7) xor drev(6) xor drev(5) xor drev(4) xor drev(2) xor drev(1) xor prev(25) xor prev(26) xor prev(28) xor prev(29) xor prev(30) xor prev(31);
    result(7)  := drev(7) xor drev(5) xor drev(3) xor drev(2) xor drev(0) xor prev(24) xor prev(26) xor prev(27) xor prev(29) xor prev(31);
    result(8)  := drev(4) xor drev(3) xor drev(1) xor drev(0) xor prev(0) xor prev(24) xor prev(25) xor prev(27) xor prev(28);
    result(9)  := drev(5) xor drev(4) xor drev(2) xor drev(1) xor prev(1) xor prev(25) xor prev(26) xor prev(28) xor prev(29);
    result(10) := drev(5) xor drev(3) xor drev(2) xor drev(0) xor prev(2) xor prev(24) xor prev(26) xor prev(27) xor prev(29);
    result(11) := drev(4) xor drev(3) xor drev(1) xor drev(0) xor prev(3) xor prev(24) xor prev(25) xor prev(27) xor prev(28);
    result(12) := drev(6) xor drev(5) xor drev(4) xor drev(2) xor drev(1) xor drev(0) xor prev(4) xor prev(24) xor prev(25) xor prev(26) xor prev(28) xor prev(29) xor prev(30);
    result(13) := drev(7) xor drev(6) xor drev(5) xor drev(3) xor drev(2) xor drev(1) xor prev(5) xor prev(25) xor prev(26) xor prev(27) xor prev(29) xor prev(30) xor prev(31);
    result(14) := drev(7) xor drev(6) xor drev(4) xor drev(3) xor drev(2) xor prev(6) xor prev(26) xor prev(27) xor prev(28) xor prev(30) xor prev(31);
    result(15) := drev(7) xor drev(5) xor drev(4) xor drev(3) xor prev(7) xor prev(27) xor prev(28) xor prev(29) xor prev(31);
    result(16) := drev(5) xor drev(4) xor drev(0) xor prev(8) xor prev(24) xor prev(28) xor prev(29);
    result(17) := drev(6) xor drev(5) xor drev(1) xor prev(9) xor prev(25) xor prev(29) xor prev(30);
    result(18) := drev(7) xor drev(6) xor drev(2) xor prev(10) xor prev(26) xor prev(30) xor prev(31);
    result(19) := drev(7) xor drev(3) xor prev(11) xor prev(27) xor prev(31);
    result(20) := drev(4) xor prev(12) xor prev(28);
    result(21) := drev(5) xor prev(13) xor prev(29);
    result(22) := drev(0) xor prev(14) xor prev(24);
    result(23) := drev(6) xor drev(1) xor drev(0) xor prev(15) xor prev(24) xor prev(25) xor prev(30);
    result(24) := drev(7) xor drev(2) xor drev(1) xor prev(16) xor prev(25) xor prev(26) xor prev(31);
    result(25) := drev(3) xor drev(2) xor prev(17) xor prev(26) xor prev(27);
    result(26) := drev(6) xor drev(4) xor drev(3) xor drev(0) xor prev(18) xor prev(24) xor prev(27) xor prev(28) xor prev(30);
    result(27) := drev(7) xor drev(5) xor drev(4) xor drev(1) xor prev(19) xor prev(25) xor prev(28) xor prev(29) xor prev(31);
    result(28) := drev(6) xor drev(5) xor drev(2) xor prev(20) xor prev(26) xor prev(29) xor prev(30);
    result(29) := drev(7) xor drev(6) xor drev(3) xor prev(21) xor prev(27) xor prev(30) xor prev(31);
    result(30) := drev(7) xor drev(4) xor prev(22) xor prev(28) xor prev(31);
    result(31) := drev(5) xor prev(23) xor prev(29);
    return result;
end function;

end package body;
