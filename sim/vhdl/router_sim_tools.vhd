--------------------------------------------------------------------------
-- Copyright 2020-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Tools for use in various router_xx simulations
--
-- Includes simple randomizer functions, and blocks for generating ARP frames.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;

package router_sim_tools is
    -- PRNG state for the rand_xx functions, below.
    shared variable rs_seed1 : positive := 518874;
    shared variable rs_seed2 : positive := 761078;

    -- Random float from [0..r)
    impure function rand_float(rmax : real := 1.0) return real;

    -- Random integer from [0..N)
    impure function rand_int(imax : positive) return natural;

    -- Random bit, with optional weighting
    impure function rand_bit(prob1 : real := 0.5) return std_logic;

    -- Random vector with N bits.
    impure function rand_vec(nbits : integer) return std_logic_vector;

    -- Random vector with N bytes.
    impure function rand_bytes(nbytes : integer) return std_logic_vector;

    -- Random IP address, not part of a reserved subnet.
    impure function rand_ip_any return ip_addr_t;

    -- Random IP address, inside or outside the designated subnet.
    impure function rand_ip_sub(
        sub_addr    : ip_addr_t;
        sub_mask    : ip_addr_t;
        in_subnet   : std_logic)
        return ip_addr_t;

    -- Test if a given IP is inside the subnet.
    function ip_in_subnet(
        tst_addr    : ip_addr_t;
        sub_addr    : ip_addr_t;
        sub_mask    : ip_addr_t)
        return boolean;

    -- Sanity-check the given std_logic_vector for L/H/Z/U/X/etc.
    -- Returns true if every bit is valid and length is byte-aligned.
    function check_vector(x : std_logic_vector) return boolean;

    -- Pull up to N bytes from start of input vector.
    function get_first_bytes(
        data    : std_logic_vector;
        nbytes  : integer) return std_logic_vector;

    -- Better concatenate function that forces "downto" slice direction.
    -- (Otherwise, some tools get unexpected runtime exceptions.)
    function concat(a,b : std_logic_vector) return std_logic_vector;

    -- Test if a given IP is in any of the "special" ranges that requires
    -- special handling.  (i.e., Any reserved address except private networks.)
    function ip_reserved(addr : ip_addr_t) return boolean;

    -- Define various commonly used protocol magic numbers:
    subtype ethertype is std_logic_vector(15 downto 0);
    subtype slv16 is std_logic_vector(15 downto 0);
    constant ETYPE_NOIP     : ethertype := x"1234";

    constant ICMP_TC_ECHORP : slv16 := x"0000";
    constant ICMP_TC_DNU    : slv16 := x"0300";
    constant ICMP_TC_DHU    : slv16 := x"0301";
    constant ICMP_TC_DPU    : slv16 := x"0302";
    constant ICMP_TC_DRU    : slv16 := x"0303";
    constant ICMP_TC_ECHORQ : slv16 := x"0800";
    constant ICMP_TC_TTL    : slv16 := x"0B00";
    constant ICMP_TC_TIMERQ : slv16 := x"0D00";
    constant ICMP_TC_TIMERP : slv16 := x"0E00";
    constant ICMP_TC_MASKRQ : slv16 := x"1100";
    constant ICMP_TC_MASKRP : slv16 := x"1200";

    constant IPFLAG_NORMAL  : slv16 := x"0000";
    constant IPFLAG_NOFRAG  : slv16 := x"4000";
    constant IPFLAG_FRAG1   : slv16 := x"2000";
    constant IPFLAG_FRAG2   : slv16 := x"0080";

    constant ARP_REQUEST    : slv16 := x"0001";
    constant ARP_REPLY      : slv16 := x"0002";

    constant ZPAD32         : ip_addr_t := (others => '0');

    -- Use quasi-pointers for variable-length packets.
    -- (Some simulators can't handle unconstrained std_logic_vector.)
    type eth_packet is access std_logic_vector;
    type ip_packet is access std_logic_vector;

    -- Structure defining an IPv4 header.
    type ipv4_header is record
        version : std_logic_vector(3 downto 0);
        dscp    : std_logic_vector(5 downto 0);
        ecn     : std_logic_vector(1 downto 0);
        ident   : bcount_t;
        flags   : std_logic_vector(2 downto 0);
        fr_off  : unsigned(12 downto 0);
        ttl     : unsigned(7 downto 0);
        proto   : byte_t;
        srcip   : ip_addr_t;
        dstip   : ip_addr_t;
    end record;

    function ipv4_checksum(x : std_logic_vector) return slv16;

    function make_ipv4_header(
        dst, src    : ip_addr_t;
        ident       : bcount_t;
        proto       : byte_t;
        flags       : slv16 := IPFLAG_NORMAL;
        ttl         : integer := 64)
        return ipv4_header;

    -- Calculate CRC of an input vector, using Ethernet CRC32 method.
    function eth_checksum(x : std_logic_vector) return crc_word_t;

    -- Make an Ethernet frame with the given parameters and payload.
    -- Note: Most router internal logic omits the FCS/CRC at end of frame.
    function make_eth_pkt(
        dst     : mac_addr_t;
        src     : mac_addr_t;
        etype   : ethertype;
        data    : std_logic_vector)
        return eth_packet;  -- Header + Data only

    function make_eth_fcs(
        dst     : mac_addr_t;
        src     : mac_addr_t;
        etype   : ethertype;
        data    : std_logic_vector)
        return eth_packet;  -- Header + Data + FCS

    function make_eth_fcs(frm : std_logic_vector)
        return eth_packet;  -- Header + Data + FCS

    -- As above but with 802.1Q VLAN tags.
    function make_vlan_pkt(
        dst     : mac_addr_t;
        src     : mac_addr_t;
        vtag    : vlan_hdr_t;
        etype   : ethertype;
        data    : std_logic_vector)
        return eth_packet;  -- Header + Tag + Data only

    function make_vlan_fcs(
        dst     : mac_addr_t;
        src     : mac_addr_t;
        vtag    : vlan_hdr_t;
        etype   : ethertype;
        data    : std_logic_vector)
        return eth_packet;  -- Header + Tag Data + FCS

    -- Make an IPv4 frame with the given parameters and payload.
    -- Note: Typically the result is passed to make_eth_pkt() or make_eth_fcs().
    function make_ipv4_pkt(
        hdr     : ipv4_header;
        data    : std_logic_vector;
        opts    : std_logic_vector := "")
        return ip_packet;

    -- Decrement the TTL counter of an IPv4-in-Ethernet frame.
    function decr_ipv4_ttl(x : std_logic_vector) return eth_packet;

    -- Make an ARP request or reply:
    function make_arp_pkt(
        op  : slv16;
        sha : mac_addr_t;
        spa : ip_addr_t;
        tha : mac_addr_t;
        tpa : ip_addr_t;
        fcs : boolean := true)
        return eth_packet;

    -- Make an ICMP request message (e.g., timestamp or echo)
    function make_icmp_request(
        dst, src    : ip_addr_t;
        opcode      : ethertype;
        ident       : bcount_t;
        refdat      : std_logic_vector;
        ttl         : integer := 64)
        return ip_packet;

    -- Make an ICMP frame that replies to the given IPv4 frame.
    -- Note: Time request / time-reply not supported.
    function make_icmp_reply(
        srcip   : ip_addr_t;
        opcode  : ethertype;
        ident   : bcount_t;
        refpkt  : std_logic_vector;
        maxecho : integer := 64)
        return ip_packet;

    -- Type codes for the ARP packet generator.
    type pkt_type_t is (PKT_JUNK, PKT_ARP_REQUEST, PKT_ARP_RESPONSE);

    -- Fixed fields for ARP frames: EtherType, HTYPE, PTYPE, HLEN, PLEN, OPER
    constant ARP_QUERY_HDR : std_logic_vector(79 downto 0) :=
        x"0806_0001_0800_06_04_0001";
    constant ARP_REPLY_HDR : std_logic_vector(79 downto 0) :=
        x"0806_0001_0800_06_04_0002";

    -- ARP packet generator.
    component router_sim_pkt_gen is
        port (
        -- Network interface
        tx_clk      : in  std_logic;
        tx_data     : out byte_t;
        tx_last     : out std_logic;
        tx_write    : out std_logic;

        -- Test control
        cmd_type    : in  pkt_type_t;
        cmd_rate    : in  real;
        cmd_start   : in  std_logic;
        cmd_busy    : out std_logic;
        cmd_sha     : in  mac_addr_t;
        cmd_spa     : in  ip_addr_t;
        cmd_tha     : in  mac_addr_t;
        cmd_tpa     : in  ip_addr_t);
    end component;
end package;

---------------------------------------------------------------------

package body router_sim_tools is
    impure function rand_float(rmax : real := 1.0) return real is
        variable rand : real;
    begin
        uniform(rs_seed1, rs_seed2, rand);
        return rand * rmax;
    end function;

    impure function rand_int(imax : positive) return natural is
        variable rand : real;
    begin
        uniform(rs_seed1, rs_seed2, rand);
        return integer(floor(rand * real(imax)));
    end function;

    impure function rand_bit(prob1 : real := 0.5) return std_logic is
        variable rand : real;
    begin
        uniform(rs_seed1, rs_seed2, rand);
        return bool2bit(rand < prob1);
    end function;

    impure function rand_vec(nbits : integer) return std_logic_vector is
        variable rand : real;
        variable tmp : std_logic_vector(nbits-1 downto 0);
    begin
        for n in tmp'range loop
            uniform(rs_seed1, rs_seed2, rand);
            tmp(n) := bool2bit(rand < 0.5);
        end loop;
        return tmp;
    end function;

    impure function rand_bytes(nbytes : integer) return std_logic_vector is
    begin
        return rand_vec(8 * nbytes);
    end function;

    impure function rand_ip_any return ip_addr_t is
        variable temp_ip : ip_addr_t := rand_vec(32);
    begin
        -- Keep rolling the dice until we get something that's not reserved.
        -- (High probability of success within 1-2 iterations.)
        while (ip_reserved(temp_ip)) loop
            temp_ip := rand_vec(32);
        end loop;
        return temp_ip;
    end function;

    impure function rand_ip_sub(
        sub_addr   : ip_addr_t;
        sub_mask   : ip_addr_t;
        in_subnet  : std_logic)
        return ip_addr_t
    is
        variable temp_ip : ip_addr_t := rand_ip_any;
    begin
        if (in_subnet = '1') then
            -- Set every bit in subnet mask to match.
            temp_ip := (sub_addr and sub_mask)
                    or (temp_ip and not sub_mask);
        else
            -- Re-roll until we get something outside the subnet.
            -- TODO: Better algorithm if requested subnet is very large?)
            while (ip_in_subnet(temp_ip, sub_addr, sub_mask)) loop
                temp_ip := rand_ip_any;
            end loop;
        end if;
        return temp_ip;
    end function;

    -- Test if a given IP is inside the subnet.
    function ip_in_subnet(
        tst_addr    : ip_addr_t;
        sub_addr    : ip_addr_t;
        sub_mask    : ip_addr_t)
        return boolean is
    begin
        return (tst_addr and sub_mask) = (sub_addr and sub_mask);
    end function;

    -- Test if a given IP is in any of the reserved ranges.
    function ip_reserved(addr : ip_addr_t) return boolean is
    begin
        -- See also: https://en.wikipedia.org/wiki/Reserved_IP_addresses
        return ip_in_subnet(addr, x"00000000", x"FF000000")  -- Source-only (0.*.*.*)
            or ip_in_subnet(addr, x"FF000000", x"FF000000")  -- Local loopback (127.*.*.*)
            or ip_in_subnet(addr, x"A9FE0000", x"FFFF0000")  -- Link-local (169.254.*.*)
            or ip_in_subnet(addr, x"E0000000", x"F0000000")  -- IP multicast (224-239.*.*.*)
            or ip_in_subnet(addr, x"FFFFFFFF", x"FFFFFFFF"); -- IP broadcast (255.255.255.255)
    end function;

    -- Sanity-check the given std_logic_vector for L/H/Z/U/X/etc.
    function check_vector(x : std_logic_vector) return boolean is
    begin
        -- Check each bit for unusual values...
        for n in x'range loop
            if (x(n) /= '0' and x(n) /= '1') then
                return false;   -- Failed sanity check.
            end if;
        end loop;
        -- Check that the length is a multiple of eight.
        return (x'length mod 8) = 0;
    end function;

    -- Pull up to N bytes from an input vector.
    function get_first_bytes(
        data    : std_logic_vector;
        nbytes  : integer) return std_logic_vector is
    begin
        if (data'length > 8*nbytes) then
            return data(data'left downto data'left+1-8*nbytes);
        else
            return data;
        end if;
    end function;

    -- Better concatenate function that forces "downto" slice direction.
    function concat(a,b : std_logic_vector) return std_logic_vector is
        constant len : integer := a'length + b'length;
        constant tmp : std_logic_vector(len-1 downto 0) := a & b;
    begin
        return tmp;
    end function;

    -- Construct a default IPv4 header object.
    function make_ipv4_header(
        dst, src    : ip_addr_t;
        ident       : bcount_t;
        proto       : byte_t;
        flags       : slv16 := IPFLAG_NORMAL;
        ttl         : integer := 64)
        return ipv4_header
    is
        constant tmp : ipv4_header := (
            version => i2s(4, 4),
            dscp    => (others => '0'),
            ecn     => (others => '0'),
            ident   => ident,
            flags   => flags(15 downto 13),
            fr_off  => unsigned(flags(12 downto 0)),
            ttl     => to_unsigned(ttl, 8),
            proto   => proto,
            srcip   => src,
            dstip   => dst);
    begin
        return tmp;
    end function;

    -- Calculate IP-checksum of a given vector.
    function ipv4_checksum(x : std_logic_vector) return slv16 is
        constant NUM_WORDS : integer := x'length / 16;
        variable chksum : ip_checksum_t := (others => '0');
        variable chktmp : slv16 := (others => '0');
     begin
        for n in NUM_WORDS-1 downto 0 loop
            chksum := ip_checksum(chksum, get_word_s(x, n));
        end loop;
        chktmp := std_logic_vector(not chksum);
        return chktmp;
    end function;

    -- Calculate CRC of an input vector, using Ethernet CRC32 method.
    function eth_checksum(x : std_logic_vector) return crc_word_t is
        variable crc, fcs : crc_word_t := CRC_INIT;
        constant NBYTES : natural := x'length / 8;
    begin
        -- Byte-at-a-time CRC calculation.
        for n in NBYTES-1 downto 0 loop
            crc := crc_next(crc, get_byte_s(x, n));
        end loop;
        -- FCS is big-endian, but LSB-first within each byte.
        for n in crc'range loop
            fcs(n) := not crc(8*(n/8) + 7 - (n mod 8));
        end loop;
        return fcs;
    end function;

    -- Make an Ethertype frame with the given parameters and payload.
    function make_eth_pkt(
        dst     : mac_addr_t;
        src     : mac_addr_t;
        etype   : ethertype;
        data    : std_logic_vector)
        return eth_packet   -- Header + Data only
    is
        constant tmp : std_logic_vector(111 + data'length downto 0)
            := dst & src & etype & data;
    begin
        return new std_logic_vector'(tmp);
    end function;

    function make_eth_fcs(
        dst     : mac_addr_t;
        src     : mac_addr_t;
        etype   : ethertype;
        data    : std_logic_vector)
        return eth_packet   -- Header + Data + FCS
    is
        constant tmp : std_logic_vector(111 + data'length downto 0)
            := dst & src & etype & data;
    begin
        return make_eth_fcs(tmp);
    end function;

    function make_eth_fcs(frm : std_logic_vector)
        return eth_packet   -- Header + Data + FCS
    is
        constant pkt : std_logic_vector(31 + frm'length downto 0)
            := frm & eth_checksum(frm);
    begin
        return new std_logic_vector'(pkt);
    end function;

    function make_vlan_pkt(
        dst     : mac_addr_t;
        src     : mac_addr_t;
        vtag    : vlan_hdr_t;
        etype   : ethertype;
        data    : std_logic_vector)
        return eth_packet
    is
        constant tmp : std_logic_vector(143 + data'length downto 0)
            := dst & src & x"8100" & vtag & etype & data;
    begin
        return new std_logic_vector'(tmp);
    end function;

    function make_vlan_fcs(
        dst     : mac_addr_t;
        src     : mac_addr_t;
        vtag    : vlan_hdr_t;
        etype   : ethertype;
        data    : std_logic_vector)
        return eth_packet
    is
        constant tmp : std_logic_vector(143 + data'length downto 0)
            := dst & src & x"8100" & vtag & etype & data;
    begin
        return make_eth_fcs(tmp);
    end function;

    function make_ipv4_pkt(
        hdr     : ipv4_header;
        data    : std_logic_vector;
        opts    : std_logic_vector := "")
        return ip_packet
    is
        -- Calculate header-length and total length for this packet:
        constant PKT_BYTES : integer := 20 + opts'length/8 + data'length/8;
        constant HDR_WORDS : integer := 5 + opts'length / 32;
        -- Concatenate header fields, before and after checksum.
        constant hdr1 : std_logic_vector(79 downto 0)
            := hdr.version & i2s(HDR_WORDS, 4) & hdr.dscp & hdr.ecn
             & i2s(PKT_BYTES, 16)
             & std_logic_vector(hdr.ident)
             & hdr.flags & std_logic_vector(hdr.fr_off)
             & std_logic_vector(hdr.ttl) & hdr.proto;
        constant hdr2 : std_logic_vector(63+opts'length downto 0)
            := hdr.srcip & hdr.dstip & opts;
        -- Calculate header checksum:
        constant chk  : slv16 := ipv4_checksum(concat(hdr1, hdr2));
        -- Full concatenated packet:
        constant pkt  : std_logic_vector(159+opts'length+data'length downto 0)
            := hdr1 & chk & hdr2 & data;
    begin
        assert (check_vector(pkt))
            report "Error forming IPv4 packet." severity failure;
        return new std_logic_vector'(pkt);
    end function;

    -- Decrement the TTL counter of an IPv4-in-Ethernet frame.
    function decr_ipv4_ttl(x : std_logic_vector) return eth_packet is
        constant XL     : natural := x'left;
        constant ttl    : unsigned(7 downto 0) := unsigned(x(XL-176 downto XL-183));
        constant chk    : ip_checksum_t := unsigned(x(XL-192 downto XL-207));
        variable y      : std_logic_vector(x'range) := x;
    begin
        -- Sanity check before we start.
        assert (check_vector(x)) report "Bad input" severity failure;
        -- Decrement the TTL field.
        y(XL-176 downto XL-183) := std_logic_vector(ttl - 1);
        -- Increment the checksum to match.
        -- Use method from IETF RFC-1624 to avoid weird edge-cases.
        y(XL-192 downto XL-207) := std_logic_vector(not ip_checksum(not chk, x"FEFF"));
        return new std_logic_vector'(y);
    end function;

    -- Make an ARP request or reply:
    function make_arp_pkt(
        op  : slv16;
        sha : mac_addr_t;
        spa : ip_addr_t;
        tha : mac_addr_t;
        tpa : ip_addr_t;
        fcs : boolean := true)
        return eth_packet
    is
        constant pkt : std_logic_vector(223 downto 0) :=
            x"000108000604" & op & sha & spa & tha & tpa;
    begin
        if (op = ARP_REQUEST and fcs) then
            return make_eth_fcs(MAC_ADDR_BROADCAST, sha, ETYPE_ARP, pkt);
        elsif (op = ARP_REQUEST and not fcs) then
            return make_eth_pkt(MAC_ADDR_BROADCAST, sha, ETYPE_ARP, pkt);
        elsif (op = ARP_REPLY and fcs) then
            return make_eth_fcs(tha, sha, ETYPE_ARP, pkt);
        elsif (op = ARP_REPLY and not fcs) then
            return make_eth_pkt(tha, sha, ETYPE_ARP, pkt);
        else
            report "Invalid ARP request" severity failure;
            return new std_logic_vector'("");
        end if;
    end function;

    -- Make an ICMP request message (e.g., timestamp or echo)
    function make_icmp_request(
        dst, src    : ip_addr_t;
        opcode      : ethertype;
        ident       : bcount_t;
        refdat      : std_logic_vector;
        ttl         : integer := 64)
        return ip_packet
    is
        -- Construct a IP new header for our reply.
        constant hdr  : ipv4_header := make_ipv4_header(
            dst, src, ident, IPPROTO_ICMP, IPFLAG_NOFRAG, ttl);
        -- Placeholder for the ICMP checksum.
        variable chk  : slv16 := ipv4_checksum(concat(opcode, refdat));
    begin
        -- Sanity check on the reference data:
        assert (check_vector(refdat)) report "Bad input" severity failure;
        -- Construct packet depending on requested opcode:
        if (opcode = ICMP_TC_ECHORQ) then       -- Echo request
            assert (refdat'length >= 64)
                report "Invalid echo data" severity warning;
            return make_ipv4_pkt(hdr, opcode & chk & refdat);
        elsif (opcode = ICMP_TC_TIMERQ) then    -- Timestamp request
            assert (refdat'length = 128)
                report "Invalid timestamp data" severity warning;
            return make_ipv4_pkt(hdr, opcode & chk & refdat);
        elsif (opcode = ICMP_TC_MASKRQ) then    -- Subnet mask request
            assert (refdat'length = 64)
                report "Invalid address mask" severity warning;
            return make_ipv4_pkt(hdr, opcode & chk & refdat);
        else
            report "Unsupported ICMP request" severity failure;
            return new std_logic_vector'("");
        end if;
    end function;

    -- Make an ICMP frame that replies to the given IP frame.
    function make_icmp_reply(
        srcip   : ip_addr_t;
        opcode  : ethertype;
        ident   : bcount_t;
        refpkt  : std_logic_vector;
        maxecho : integer := 64)
        return ip_packet
    is
        -- Extract the source IP address from original header -> reply destination.
        constant dst  : ip_addr_t := refpkt(refpkt'left-96 downto refpkt'left-127);
        -- Construct a IP new header for our reply, swapping source and destination.
        constant hdr  : ipv4_header := make_ipv4_header(
            dst, srcip, ident, IPPROTO_ICMP, IPFLAG_NOFRAG);
        -- Common fields used in ICMP replies.
        constant rpkt : std_logic_vector := get_first_bytes(refpkt, maxecho);
        constant rdat : std_logic_vector := get_first_bytes(refpkt(refpkt'left-192 downto 0), maxecho);
        -- Placeholder for the ICMP checksum.
        variable chk  : slv16 := (others => '0');
    begin
        -- Sanity check that reference is an IPv4 frame, not an Ethernet frame.
        assert (check_vector(refpkt))
            report "Input contains invalid values." severity failure;
        assert (get_first_bytes(refpkt, 1) = x"45")
            report "Input may not be an IPv4 frame." severity warning;
        -- Construct the requested packet:
        if (opcode = ICMP_TC_ECHORP or      -- Echo reply
            opcode = ICMP_TC_MASKRP or      -- Address mask reply
            opcode = ICMP_TC_TIMERP) then   -- Timestamp reply
            chk := ipv4_checksum(concat(opcode, rdat));
            return make_ipv4_pkt(hdr, opcode & chk & rdat);
        elsif (opcode = ICMP_TC_TTL) then   -- Time exceeded
            chk := ipv4_checksum(concat(opcode, rpkt));
            return make_ipv4_pkt(hdr, opcode & chk & ZPAD32 & rpkt);
        elsif (opcode = ICMP_TC_DNU
            or opcode = ICMP_TC_DHU
            or opcode = ICMP_TC_DPU
            or opcode = ICMP_TC_DRU) then   -- Destination unreachable
            chk := ipv4_checksum(concat(opcode, rpkt));
            return make_ipv4_pkt(hdr, opcode & chk & ZPAD32 & rpkt);
        else
            report "Unsupported ICMP reply" severity error;
            return new std_logic_vector'("");
        end if;
    end function;
end package body;

---------------------------------------------------------------------

library ieee;
use     ieee.math_real.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;

entity router_sim_pkt_gen is
    port (
    -- Network interface
    tx_clk      : in  std_logic;
    tx_data     : out byte_t;
    tx_last     : out std_logic;
    tx_write    : out std_logic;

    -- Test control
    cmd_type    : in  pkt_type_t;
    cmd_rate    : in  real;
    cmd_start   : in  std_logic;
    cmd_busy    : out std_logic;
    cmd_sha     : in  mac_addr_t;
    cmd_spa     : in  ip_addr_t;
    cmd_tha     : in  mac_addr_t;
    cmd_tpa     : in  ip_addr_t);
end router_sim_pkt_gen;

architecture router_sim_pkt_gen of router_sim_pkt_gen is

signal tx_data_i    : byte_t := (others => '0');
signal tx_last_i    : std_logic := '0';
signal tx_write_i   : std_logic := '0';
signal cmd_busy_i   : std_logic := '0';

begin

tx_data  <= tx_data_i;
tx_last  <= tx_last_i;
tx_write <= tx_write_i;
cmd_busy <= cmd_busy_i;

p_pkt_gen : process
    variable seed1  : positive := 12345;
    variable seed2  : positive := 67890;
    variable rand   : real := 0.0;
    variable bcount : integer := 0;

    -- Send a single byte.
    procedure send_byte(x:byte_t; last:std_logic) is
    begin
        -- Flow-control randomization.
        uniform(seed1, seed2, rand);
        while (rand >= cmd_rate) loop
            tx_write_i <= '0';
            uniform(seed1, seed2, rand);
            wait until rising_edge(tx_clk);
        end loop;
        -- Send the next byte.
        tx_data_i  <= x;
        tx_last_i  <= last;
        tx_write_i <= '1';
        wait until rising_edge(tx_clk);
    end procedure;

    -- Send a sequence of bytes in big-endian order.
    procedure send_vec(x:std_logic_vector; last:std_logic) is
        constant nbytes : integer := x'length / 8;
    begin
        for n in nbytes-1 downto 0 loop
            send_byte(get_byte_s(x, n), bool2bit(last='1' and n=0));
        end loop;
    end procedure;
begin
    -- Idle until we get a start strobe...
    tx_data_i   <= (others => '0');
    tx_last_i   <= '0';
    tx_write_i  <= '0';
    cmd_busy_i  <= '0';
    wait until rising_edge(cmd_start);
    cmd_busy_i  <= '1';
    wait until rising_edge(tx_clk);

    if (cmd_type = PKT_ARP_REQUEST) then
        -- How much padding should we add?
        bcount := rand_int(8);
        -- Send a valid ARP request:
        send_vec(MAC_ADDR_BROADCAST, '0');
        send_vec(cmd_sha, '0');
        send_vec(ARP_QUERY_HDR, '0');
        send_vec(cmd_sha, '0');
        send_vec(cmd_spa, '0');
        send_vec(cmd_tha, '0');
        send_vec(cmd_tpa, bool2bit(bcount=0));
    elsif (cmd_type = PKT_ARP_RESPONSE) then
        -- How much padding should we add?
        bcount := rand_int(8);
        -- Send a valid ARP reply:
        send_vec(MAC_ADDR_BROADCAST, '0');
        send_vec(cmd_sha, '0');
        send_vec(ARP_REPLY_HDR, '0');
        send_vec(cmd_sha, '0');
        send_vec(cmd_spa, '0');
        send_vec(cmd_tha, '0');
        send_vec(cmd_tpa, bool2bit(bcount=0));
    else
        -- Send anywhere from 1-100 random bytes:
        bcount := 1 + rand_int(100);
    end if;

    -- Send random bytes (main packet or padding).
    while (bcount > 0) loop
        bcount := bcount - 1;
        send_byte(i2s(rand_int(256), 8), bool2bit(bcount = 0));
    end loop;
end process;

end router_sim_pkt_gen;
