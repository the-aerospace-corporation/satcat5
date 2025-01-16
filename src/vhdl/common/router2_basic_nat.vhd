--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Basic Network Address Translation (NAT)
--
-- This block implements "Basic NAT" as defined in IETF RFC-3022:
--  https://www.rfc-editor.org/rfc/rfc3022
--
-- We assume that the internal and external address ranges are equal
-- in size, allowing trivial one-to-one mapping of subnet addresses.
-- As such, this block must perform the following steps:
--  * Discard the Ethernet FCS field, if present.
--  * If enabled, inspect ARP packets and update SPA/TPA as needed.
--  * Inspect IPv4 source address and update as needed.
--  * Inspect IPv4 destination address and update as needed.
--  * Update checksums in the IP, TCP, and UDP headers.
--  * As-is passthrough for all other packet types.
--  * Optionally recalculate and append a new Ethernet FCS.
--
-- Checksums are updated using the incremental algorithm documented in
-- IETF RFC 1624, allowing updates without reading the packet contents:
--  https://www.rfc-editor.org/rfc/rfc1624
--
-- Since this block may be used at both ingress and egress, the direction
-- is configurable to allow simultaneous configuration.  If MODE_IG is true
-- (ingress), then internal/denormalized addresses in the input are normalized
-- in the output; otherwise, the address conversion is reversed for egress.
--
-- NAT configuration may vary between ports.  If all ports are configured
-- identically, set PORT_INDEX = -1. Otherwise, instantiate multiple blocks
-- with unique PORT_INDEX values, and include the index in ConfigBus commands.
--
-- The internal and external address ranges can be specified at build-time,
-- or at runtime through an optional ConfigBus interface:
--  * RT_ADDR_NAT_CTRL: 3x write, then read to apply
--      Write the internal/denormalized base address.
--      Write the external/normalized base address.
--      Write the command word:
--          Bits 31..24 = Port number (0-31) if applicable, otherwise zero.
--          Bits 23..16 = Subnet prefix length (1-32) or disabled (0)
--          Bits 15..00 = Reserved (write zeros)
--      Read the register to latch the new command word.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router2_common.all;

entity router2_basic_nat is
    generic (
    -- General-purpose setup.
    IO_BYTES    : positive;                     -- Width of datapath
    MODE_IG     : boolean;                      -- Ingress or egress (see top)
    PORT_INDEX  : integer := -1;                -- Router port number (-1 = any)
    DEVADDR     : integer := CFGBUS_ADDR_NONE;  -- ConfigBus address (optional)
    MIN_FRAME   : natural := 0;                 -- Zero-pad Ethernet frames?
    APPEND_FCS  : boolean := true;              -- Append new FCS to output?
    ENABLE_ARP  : boolean := true;              -- Support for ARP translation?
    ENABLE_NAT  : boolean := true;              -- Enable NAT or bypass?
    ENABLE_VLAN : boolean := true;              -- Support for 802.1q VLAN?
    STRIP_FCS   : boolean := true;              -- Remove FCS from input?
    -- Optionally set the default address map.
    ADDR_INT    : ip_addr_t := IP_NOT_VALID;    -- Internal base address
    ADDR_EXT    : ip_addr_t := IP_NOT_VALID;    -- External base address
    ADDR_PLEN   : natural := 0);                -- Subnet prefix length
    port (
    -- Input data stream uses AXI Stream interface.
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;
    -- Output data stream uses AXI Stream interface.
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;
    -- Optional ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;
    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end router2_basic_nat;

architecture router2_basic_nat of router2_basic_nat is

-- Local type definitions.
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype daug_t is std_logic_vector(8*IO_BYTES+7 downto 0);
subtype meta_t is std_logic_vector(9 downto 0);
subtype last_t is integer range 0 to IO_BYTES;

-- Required buffer depth is 64 bytes <= 2^N words to avoid deadlock,
function get_fifo_depth return positive is
begin
    if IO_BYTES = 1 then
        return 6;   -- 2^6 = 64 words
    elsif IO_BYTES = 2 or IO_BYTES = 3 then
        return 5;   -- 2^5 = 32 words
    else
        return 4;   -- 2^4 = 16 words
    end if;
end function;

-- Maximum byte-index of interest is end of the TCP checksum field.
-- (Plus 2 bytes for the field itself, plus four bytes for a VLAN tag.)
constant BCOUNT_MAX : integer := 6 + TCP_HDR_CHK(IP_IHL_MAX);
constant WCOUNT_MAX : integer := 1 + BCOUNT_MAX / IO_BYTES;
subtype counter_t is integer range 0 to WCOUNT_MAX;

-- First-pass parsing.
signal in_ready_i   : std_logic;
signal in_write     : std_logic;
signal in_wcount    : counter_t := 0;
signal parse_meta   : meta_t := (others => '0');
signal parse_write  : std_logic := '0';

-- Data and metadata FIFOs.
signal dly_data     : daug_t := (others => '0');
signal dly_nlast    : last_t := 0;
signal dly_valid1   : std_logic := '0';
signal dly_valid2   : std_logic := '0';
signal dly_ready    : std_logic;
signal dly_final    : std_logic;
signal dly_meta     : meta_t;
signal dly_wcount   : counter_t := 0;

-- Second-pass parsing.
signal adj_data     : data_t := (others => '0');
signal adj_nlast    : last_t := 0;
signal adj_valid    : std_logic := '0';
signal adj_ready    : std_logic;

-- Configuration logic.
signal cfg_ack_i    : cfgbus_ack;
signal cpu_wren     : std_logic := '0';
signal cpu_word     : std_logic_vector(95 downto 0);
signal nat_diff     : ip_checksum_t := (others => '0');
signal nat_in       : ip_addr_t;
signal nat_out      : ip_addr_t;
signal nat_int      : ip_addr_t := ADDR_INT;
signal nat_ext      : ip_addr_t := ADDR_EXT;
signal nat_mask     : ip_addr_t := ip_prefix2mask(ADDR_PLEN);

begin

-- Upstream flow-control.
in_ready    <= in_ready_i;
in_write    <= in_valid and in_ready_i;

-- Bypass mode?
gen0 : if not ENABLE_NAT generate
    adj_data    <= in_data;
    adj_nlast   <= in_nlast;
    adj_valid   <= in_valid;
    in_ready_i  <= adj_ready;
end generate;

-- Normal mode?
gen1 : if ENABLE_NAT generate
    -- First-pass parsing (read-only):
    --  * If enabled, identify and skip 802.1q VLAN tags.
    --  * Identify protocols of interest (IPv4+TCP, IPv4+UDP, IPv4+Other).
    --  * Read source and destination IP-address, then match against template.
    p_parse : process(clk)
        -- Set limit for parsing in this section:
        --  * ARP header: 46 bytes
        --    (14-byte Eth header + 4-byte VLAN tag + 28-byte ARP header)
        --  * IPv4 header, ignoring options: 38 bytes
        --    (14-byte Eth header + 4-byte VLAN tag + 20-byte IPv4 header)
        constant BCOUNT_FIN : positive := 46;   -- Max of above limits
        constant WCOUNT_FIN : positive := (BCOUNT_FIN - 1) / IO_BYTES;
        -- Internal state uses variables to simplify sequential parsing.
        -- Note: Some of these are used by the impure functions below.
        variable parse_ihl  : nybb_t := (others => '0');
        variable parse_arp  : std_logic := '0';
        variable parse_ip   : std_logic := '0';
        variable parse_tcp  : std_logic := '0';
        variable parse_udp  : std_logic := '0';
        variable parse_vlan : std_logic := '0';
        variable parse_src  : ip_addr_t := (others => '0');
        variable parse_dst  : ip_addr_t := (others => '0');
        -- Thin wrapper for the stream-to-byte extractor functions.
        variable btmp : byte_t := (others => '0');  -- Stores output
        impure function get_eth_byte(bidx : natural) return boolean is
        begin
            btmp := strm_byte_value(IO_BYTES, bidx, in_data);
            return strm_byte_present(IO_BYTES, bidx, in_wcount);
        end function;
        impure function get_vlan_byte(bidx : natural) return boolean is
            variable btag : natural := bidx + 4 * u2i(parse_vlan);
        begin
            return get_eth_byte(btag);
        end function;
        -- Does a given IP address match the translated subnet?
        impure function ip_match(ip : ip_addr_t) return std_logic is
        begin
            return bool2bit((ip and nat_mask) = (nat_in and nat_mask));
        end function;
    begin
        if rising_edge(clk) then
            -- Word count synchronized with the "in_data" stream.
            if (reset_p = '1') then
                in_wcount <= 0;                 -- Global reset
            elsif (in_write = '1' and in_nlast > 0) then
                in_wcount <= 0;                 -- Start of new frame
            elsif (in_write = '1' and in_wcount < WCOUNT_MAX) then
                in_wcount <= in_wcount + 1;     -- Count up to max
            end if;

            -- Parse each input word...
            if (in_write = '1') then
                -- Outer EtherType (2 bytes)
                if (get_eth_byte(ETH_HDR_ETYPE+0)) then
                    parse_arp   := bool2bit(btmp = ETYPE_ARP(15 downto 8) and ENABLE_ARP);
                    parse_ip    := bool2bit(btmp = ETYPE_IPV4(15 downto 8));
                    parse_vlan  := bool2bit(btmp = ETYPE_VLAN(15 downto 8) and ENABLE_VLAN);
                end if;
                if (get_eth_byte(ETH_HDR_ETYPE+1)) then
                    parse_arp   := parse_arp  and bool2bit(btmp = ETYPE_ARP(7 downto 0));
                    parse_ip    := parse_ip   and bool2bit(btmp = ETYPE_IPV4(7 downto 0));
                    parse_vlan  := parse_vlan and bool2bit(btmp = ETYPE_VLAN(7 downto 0));
                end if;
                -- Inner EtherType (2 bytes, VLAN only)
                -- Note: Everything below this point implicitly depends on the
                --  "parse_vlan" flag, because VLAN tags add a four-byte offset.
                if (ENABLE_VLAN and parse_vlan = '1') then
                    if (get_vlan_byte(ETH_HDR_ETYPE+0)) then
                        parse_arp   := bool2bit(btmp = ETYPE_ARP(15 downto 8) and ENABLE_ARP);
                        parse_ip    := bool2bit(btmp = ETYPE_IPV4(15 downto 8));
                    end if;
                    if (get_vlan_byte(ETH_HDR_ETYPE+1)) then
                        parse_arp   := parse_arp and bool2bit(btmp = ETYPE_ARP(7 downto 0));
                        parse_ip    := parse_ip  and bool2bit(btmp = ETYPE_IPV4(7 downto 0));
                    end if;
                end if;
                -- ARP protocol type (HTYPE = Ethernet, PTYPE = IPv4)
                if (get_vlan_byte(ARP_HDR_HTYPE+0)) then
                    parse_arp := parse_arp and bool2bit(btmp = ARP_HTYPE_ETH(15 downto 8));
                end if;
                if (get_vlan_byte(ARP_HDR_HTYPE+1)) then
                    parse_arp := parse_arp and bool2bit(btmp = ARP_HTYPE_ETH(7 downto 0));
                end if;
                if (get_vlan_byte(ARP_HDR_PTYPE+0)) then
                    parse_arp := parse_arp and bool2bit(btmp = ARP_PTYPE_IPV4(15 downto 8));
                end if;
                if (get_vlan_byte(ARP_HDR_PTYPE+1)) then
                    parse_arp := parse_arp and bool2bit(btmp = ARP_PTYPE_IPV4(7 downto 0));
                end if;
                -- ARP sender address (SPA, 4 bytes)
                if (get_vlan_byte(ARP_HDR_SPA+0) and parse_arp = '1') then
                    parse_src(31 downto 24) := btmp;
                end if;
                if (get_vlan_byte(ARP_HDR_SPA+1) and parse_arp = '1') then
                    parse_src(23 downto 16) := btmp;
                end if;
                if (get_vlan_byte(ARP_HDR_SPA+2) and parse_arp = '1') then
                    parse_src(15 downto 8) := btmp;
                end if;
                if (get_vlan_byte(ARP_HDR_SPA+3) and parse_arp = '1') then
                    parse_src(7 downto 0) := btmp;
                end if;
                -- ARP target address (TPA, 4 bytes)
                if (get_vlan_byte(ARP_HDR_TPA+0) and parse_arp = '1') then
                    parse_dst(31 downto 24) := btmp;
                end if;
                if (get_vlan_byte(ARP_HDR_TPA+1) and parse_arp = '1') then
                    parse_dst(23 downto 16) := btmp;
                end if;
                if (get_vlan_byte(ARP_HDR_TPA+2) and parse_arp = '1') then
                    parse_dst(15 downto 8) := btmp;
                end if;
                if (get_vlan_byte(ARP_HDR_TPA+3) and parse_arp = '1') then
                    parse_dst(7 downto 0) := btmp;
                end if;
                -- IPv4 version + IHL (1 byte)
                if (get_vlan_byte(IP_HDR_VERSION)) then
                    if (parse_ip = '1' and btmp(7 downto 4) = x"4") then
                        parse_ip  := '1';
                        parse_ihl := btmp(3 downto 0);
                    else
                        parse_ip  := '0';
                        parse_ihl := (others => '0');
                    end if;
                end if;
                -- IPv4 protocol (1 byte)
                if (get_vlan_byte(IP_HDR_PROTOCOL)) then
                    parse_tcp   := parse_ip and bool2bit(btmp = IPPROTO_TCP);
                    parse_udp   := parse_ip and bool2bit(btmp = IPPROTO_UDP);
                end if;
                -- IPv4 source (4 bytes)
                if (get_vlan_byte(IP_HDR_SRCADDR+0) and parse_ip = '1') then
                    parse_src(31 downto 24) := btmp;
                end if;
                if (get_vlan_byte(IP_HDR_SRCADDR+1) and parse_ip = '1') then
                    parse_src(23 downto 16) := btmp;
                end if;
                if (get_vlan_byte(IP_HDR_SRCADDR+2) and parse_ip = '1') then
                    parse_src(15 downto 8) := btmp;
                end if;
                if (get_vlan_byte(IP_HDR_SRCADDR+3) and parse_ip = '1') then
                    parse_src(7 downto 0) := btmp;
                end if;
                -- IPv4 destination (4 bytes)
                if (get_vlan_byte(IP_HDR_DSTADDR+0) and parse_ip = '1') then
                    parse_dst(31 downto 24) := btmp;
                end if;
                if (get_vlan_byte(IP_HDR_DSTADDR+1) and parse_ip = '1') then
                    parse_dst(23 downto 16) := btmp;
                end if;
                if (get_vlan_byte(IP_HDR_DSTADDR+2) and parse_ip = '1') then
                    parse_dst(15 downto 8) := btmp;
                end if;
                if (get_vlan_byte(IP_HDR_DSTADDR+3) and parse_ip = '1') then
                    parse_dst(7 downto 0) := btmp;
                end if;
            end if;

            -- Pack metadata so it can be written to the FIFO.
            -- Write strobe on WCOUNT_FIN or end-of-frame, whichever comes first.
            parse_meta <= parse_arp & parse_tcp & parse_udp & parse_vlan
                & ip_match(parse_src) & ip_match(parse_dst) & parse_ihl;
            parse_write <= in_write and bool2bit(
                (in_wcount = WCOUNT_FIN) or
                (in_wcount < WCOUNT_FIN and in_nlast > 0));
        end if;
    end process;

    -- Buffer input for second-pass parsing.
    -- (Augment output with an extra byte to ease checksum calculations.)
    u_fifo : entity work.packet_augment
        generic map(
        IN_BYTES    => IO_BYTES,
        OUT_BYTES   => IO_BYTES + 1,
        DEPTH_LOG2  => get_fifo_depth)
        port map(
        in_data     => in_data,
        in_nlast    => in_nlast,
        in_valid    => in_valid,
        in_ready    => in_ready_i,
        out_data    => dly_data,
        out_nlast   => dly_nlast,
        out_valid   => dly_valid1,
        out_ready   => dly_ready,
        clk         => clk,
        reset_p     => reset_p);

    -- Metadata FIFO for parsing results.
    u_meta : entity work.fifo_smol_sync
        generic map(IO_WIDTH => parse_meta'length)
        port map(
        in_data     => parse_meta,
        in_write    => parse_write,
        out_data    => dly_meta,
        out_valid   => dly_valid2,
        out_read    => dly_final,
        clk         => clk,
        reset_p     => reset_p);

    -- Flow-control waits until data and metadata are both ready.
    -- Read the metadata concurrently with the last word of the data.
    dly_ready <= (dly_valid1 and dly_valid2) and (adj_ready or not adj_valid);
    dly_final <= dly_ready and bool2bit(dly_nlast > 0);

    -- Second-pass parsing and adjustment (read-modify-write):
    --  * Update source and/or destination IP-address.
    --  * Update IP, TCP, and UDP header checksums.
    p_adj : process(clk)
        -- Metadata from the first-stage parser.
        variable parse_ihl  : nybb_u := (others => '0');
        variable parse_arp  : std_logic := '0';
        variable parse_ip   : std_logic := '0';
        variable parse_tcp  : std_logic := '0';
        variable parse_udp  : std_logic := '0';
        variable parse_vlan : std_logic := '0';
        variable parse_src  : std_logic := '0';
        variable parse_dst  : std_logic := '0';
        -- Thin wrapper for the stream-to-byte extractor functions.
        impure function is_eth_byte(n, bidx: natural) return boolean is
            variable btag : natural := bidx + 4 * u2i(parse_vlan);
            variable bmod : natural := btag mod IO_BYTES;
        begin
            return (n = bmod) and strm_byte_present(IO_BYTES, btag, dly_wcount);
        end function;
        -- Additional thin wrappers for specific protocols.
        impure function is_arp_byte(n, bidx: natural) return boolean is
        begin
            return (parse_arp = '1') and is_eth_byte(n, bidx);
        end function;
        impure function is_ip_byte(n, bidx: natural) return boolean is
        begin
            return (parse_ip = '1') and is_eth_byte(n, bidx);
        end function;
        -- Read and invert the header checksum using the RFC 1624 method.
        impure function read_checksum(n: natural) return ip_checksum_t is
            variable tmp : ip_checksum_t :=
                unsigned(not strm_byte_value(n+0, dly_data)) &
                unsigned(not strm_byte_value(n+1, dly_data));
        begin
            return tmp;
        end function;
        -- Replace the Nth byte of the designated IP address.
        impure function replace_ipaddr(n: natural; x: byte_t) return byte_t is
            variable m : byte_t := strm_byte_value(n, nat_mask);
            variable y : byte_t := strm_byte_value(n, nat_out);
            variable z : byte_t := (x and not m) or (y and m);
        begin
            return z;
        end function;
        -- Other internal state.
        variable btmp       : byte_t := (others => '0');
        variable chk_incr   : ip_checksum_t := (others => '0');
        variable chk_temp   : unsigned(15 downto 0) := (others => '0');
    begin
        if rising_edge(clk) then
            -- Word count synchronized with the "dly_data" stream.
            if (reset_p = '1') then
                dly_wcount <= 0;                -- Global reset
            elsif (dly_ready = '1' and dly_nlast > 0) then
                dly_wcount <= 0;                -- Start of new frame
            elsif (dly_ready = '1' and dly_wcount < WCOUNT_MAX) then
                dly_wcount <= dly_wcount + 1;   -- Count up to max
            end if;

            -- Unpack metadata from first-stage parsing.
            parse_arp   := dly_meta(9) and bool2bit(ENABLE_ARP);
            parse_tcp   := dly_meta(8);
            parse_udp   := dly_meta(7);
            parse_vlan  := dly_meta(6) and bool2bit(ENABLE_VLAN);
            parse_src   := dly_meta(5);
            parse_dst   := dly_meta(4);
            parse_ihl   := unsigned(dly_meta(3 downto 0));
            parse_ip    := or_reduce(dly_meta(3 downto 0));

            -- Read and modify each input word...
            if (dly_ready = '1') then
                adj_nlast <= dly_nlast;
                for n in 0 to IO_BYTES-1 loop
                    -- Read the original byte from "dly_data".
                    btmp := strm_byte_value(n, dly_data);
                    -- Update the IPv4 header checksum (2 bytes).
                    if (is_ip_byte(n, IP_HDR_CHECKSUM + 0)) then
                        chk_temp := ip_checksum(read_checksum(n), chk_incr);
                        btmp := not std_logic_vector(chk_temp(15 downto 8));
                    elsif (is_ip_byte(n, IP_HDR_CHECKSUM + 1)) then
                        btmp := not std_logic_vector(chk_temp(7 downto 0));
                    -- Replace masked portion of IPv4 source address (4 bytes).
                    elsif (parse_src = '1' and is_ip_byte(n, IP_HDR_SRCADDR + 0)) then
                        btmp := replace_ipaddr(0, btmp);
                    elsif (parse_src = '1' and is_ip_byte(n, IP_HDR_SRCADDR + 1)) then
                        btmp := replace_ipaddr(1, btmp);
                    elsif (parse_src = '1' and is_ip_byte(n, IP_HDR_SRCADDR + 2)) then
                        btmp := replace_ipaddr(2, btmp);
                    elsif (parse_src = '1' and is_ip_byte(n, IP_HDR_SRCADDR + 3)) then
                        btmp := replace_ipaddr(3, btmp);
                    -- Replace masked portion of IPv4 destination address (4 bytes).
                    elsif (parse_dst = '1' and is_ip_byte(n, IP_HDR_DSTADDR + 0)) then
                        btmp := replace_ipaddr(0, btmp);
                    elsif (parse_dst = '1' and is_ip_byte(n, IP_HDR_DSTADDR + 1)) then
                        btmp := replace_ipaddr(1, btmp);
                    elsif (parse_dst = '1' and is_ip_byte(n, IP_HDR_DSTADDR + 2)) then
                        btmp := replace_ipaddr(2, btmp);
                    elsif (parse_dst = '1' and is_ip_byte(n, IP_HDR_DSTADDR + 3)) then
                        btmp := replace_ipaddr(3, btmp);
                    -- Update the TCP header checksum (2 bytes).
                    elsif (parse_tcp = '1' and is_eth_byte(n, TCP_HDR_CHK(parse_ihl) + 0)) then
                        chk_temp := ip_checksum(read_checksum(n), chk_incr);
                        btmp := not std_logic_vector(chk_temp(15 downto 8));
                    elsif (parse_tcp = '1' and is_eth_byte(n, TCP_HDR_CHK(parse_ihl) + 1)) then
                        btmp := not std_logic_vector(chk_temp(7 downto 0));
                    -- Disable the UDP header checksum (2 bytes).
                    elsif (parse_udp = '1' and is_eth_byte(n, UDP_HDR_CHK(parse_ihl) + 0)) then
                        btmp := (others => '0');
                    elsif (parse_udp = '1' and is_eth_byte(n, UDP_HDR_CHK(parse_ihl) + 1)) then
                        btmp := (others => '0');
                    -- Replace masked portion of ARP sender address (4 bytes).
                    elsif (parse_src = '1' and is_arp_byte(n, ARP_HDR_SPA + 0)) then
                        btmp := replace_ipaddr(0, btmp);
                    elsif (parse_src = '1' and is_arp_byte(n, ARP_HDR_SPA + 1)) then
                        btmp := replace_ipaddr(1, btmp);
                    elsif (parse_src = '1' and is_arp_byte(n, ARP_HDR_SPA + 2)) then
                        btmp := replace_ipaddr(2, btmp);
                    elsif (parse_src = '1' and is_arp_byte(n, ARP_HDR_SPA + 3)) then
                        btmp := replace_ipaddr(3, btmp);
                    -- Replace masked portion of ARP target address (4 bytes).
                    elsif (parse_dst = '1' and is_arp_byte(n, ARP_HDR_TPA + 0)) then
                        btmp := replace_ipaddr(0, btmp);
                    elsif (parse_dst = '1' and is_arp_byte(n, ARP_HDR_TPA + 1)) then
                        btmp := replace_ipaddr(1, btmp);
                    elsif (parse_dst = '1' and is_arp_byte(n, ARP_HDR_TPA + 2)) then
                        btmp := replace_ipaddr(2, btmp);
                    elsif (parse_dst = '1' and is_arp_byte(n, ARP_HDR_TPA + 3)) then
                        btmp := replace_ipaddr(3, btmp);
                    end if;
                    -- Write the modified byte to "adj_data".
                    adj_data(adj_data'left-8*n downto adj_data'left-8*n-7) <= btmp;
                end loop;
            end if;

            -- Update the "valid" strobe.
            if (reset_p = '1') then
                adj_valid <= '0';           -- Global reset
            elsif (dly_ready = '1') then
                adj_valid <= '1';           -- New data written
            elsif (adj_ready = '1') then
                adj_valid <= '0';           -- Previous data consumed
            end if;

            -- Precalculate the required change in each IP/TCP/UDP checksum.
            -- (This isn't needed until ~byte 24, so some delay is OK.)
            if (parse_src = '0' and parse_dst = '0') then
                chk_incr := (others => '0');    -- No change
            elsif (parse_src = '0' or parse_dst = '0') then
                chk_incr := nat_diff;
            else
                chk_incr := ip_checksum(nat_diff, nat_diff);
            end if;
        end if;
    end process;

    -- Convert internal/external addresses to input/output.
    nat_in  <= (nat_int and nat_mask) when MODE_IG else (nat_ext and nat_mask);
    nat_out <= (nat_ext and nat_mask) when MODE_IG else (nat_int and nat_mask);

    -- Port-specific configuration logic.
    p_cfg : process(clk)
        variable cpu_temp : integer range 0 to 255 := 0;
    begin
        if rising_edge(clk) then
            -- Filter configuration changes by port index.
            if (reset_p = '1') then
                -- System reset.
                nat_int  <= ADDR_INT;
                nat_ext  <= ADDR_EXT;
                nat_mask <= ip_prefix2mask(ADDR_PLEN);
            elsif (cpu_wren = '1') then
                -- Respond to writes only if the port index matches.
                cpu_temp := u2i(cpu_word(31 downto 24));
                if (PORT_INDEX < 0 or PORT_INDEX = cpu_temp) then
                    cpu_temp := u2i(cpu_word(23 downto 16));
                    nat_int  <= cpu_word(95 downto 64);
                    nat_ext  <= cpu_word(63 downto 32);
                    nat_mask <= ip_prefix2mask(cpu_temp);
                end if;
            end if;

            -- Precalculate the effects of the configured address change.
            -- (Using the ~m + m' method of RFC1624 Section 3.)
            nat_diff <= ip_increment(nat_in, nat_out);
        end if;
    end process;
end generate;

-- Optionally remove and recalculate Ethernet FCS.
u_adj : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => MIN_FRAME,
    APPEND_FCS  => APPEND_FCS,
    STRIP_FCS   => STRIP_FCS,
    IO_BYTES    => IO_BYTES)
    port map(
    in_data     => adj_data,
    in_nlast    => adj_nlast,
    in_valid    => adj_valid,
    in_ready    => adj_ready,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Shared configuration logic.
-- Note: Since this is a shared ConfigBus register, only one instance responds.
--  This logic must function even if NAT is disabled on port zero.
cfg_ack <= cfg_ack_i when (MODE_IG and PORT_INDEX < 1) else CFGBUS_IDLE;

u_cfg : cfgbus_register_wide
    generic map(
    DWIDTH      => 96,
    DEVADDR     => DEVADDR,
    REGADDR     => RT_ADDR_NAT_CTRL)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack_i,
    sync_clk    => clk,
    sync_val    => cpu_word,
    sync_wr     => cpu_wren);

end router2_basic_nat;
