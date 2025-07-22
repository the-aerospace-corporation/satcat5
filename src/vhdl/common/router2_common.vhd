--------------------------------------------------------------------------
-- Copyright 2024-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Package definition: Useful constants and functions for router2_xx blocks
--
-- This package define a variety of constants and functions for manipulating
-- Ethernet and IPv4 frames, to maximize code reuse among various blocks.
-- It supersedes the "router_common" package from the older router design.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

package router2_common is
    -- IPv4 address (or subnet mask, etc.) is 32 bits long.
    subtype ip_addr_t is std_logic_vector(31 downto 0);
    constant IP_NOT_VALID : ip_addr_t := (others => '0');
    constant IP_BROADCAST : ip_addr_t := (others => '1');

    -- Functions for checking special IP addresses:
    function ip_in_subnet(ip1, ip2, mask : ip_addr_t) return boolean;
    function ip_is_reserved(ip : ip_addr_t) return boolean;
    function ip_is_multicast(ip : ip_addr_t) return boolean;
    function ip_is_broadcast(ip : ip_addr_t) return boolean;

    -- Convert a CIDR prefix-length to a bit-mask.
    function ip_prefix2mask(plen : natural) return ip_addr_t;

    -- One's complement sum with carry for verifying IPv4 checksum.
    -- (IETF RFC 1071: "Computing the Internet Checksum")
    subtype ip_checksum_t is unsigned(15 downto 0);
    function ip_checksum(a, b: ip_checksum_t) return ip_checksum_t;
    function ip_checksum(a: ip_checksum_t; x: std_logic_vector; bidx: natural := 0) return ip_checksum_t;
    function ip_checksum(x: std_logic_vector; bidx: natural := 0) return ip_checksum_t;

    -- Incremental IPv4 checksum update using before/after values.
    function ip_increment(pre, post: std_logic_vector) return ip_checksum_t;

    -- Use 16-bit counters for Ethernet frame lengths.
    subtype bcount_t is unsigned(15 downto 0);
    constant BCOUNT_MAX : bcount_t := (others => '1');

    -- Get the Nth byte or word from a longer vector, counting from LSB.
    -- TODO: Is this still needed?
    function get_byte_s(x:std_logic_vector; idx:integer) return byte_t;
    function get_byte_u(x:unsigned; idx:integer) return byte_t;
    function get_word_s(x:std_logic_vector; idx:integer) return ip_checksum_t;
    function get_word_u(x:unsigned; idx:integer) return ip_checksum_t;

    -- ConfigBus register addresses for configuring the router:
    --  * Reg 000-399:  Offload Tx/Rx buffer (see router2_mailmap.vhd)
    --  * Reg 400-488:  Reserved
    --  * Reg 489:      Packet logging diagnostics (see mag_log_cfgbus.vhd)
    --  * Reg 490:      VLAN configuration (see mac_vlan_mask.vhd)
    --  * Reg 491:      VLAN configuration (see mac_vlan_mask.vhd)
    --  * Reg 492:      VLAN rate-control (see mac_vlan_rate.vhd)
    --  * Reg 493:      Diagnostic packet counter (cfgbus_counter)
    --  * Reg 494:      Per-port link status (see router2_gateway.vhd)
    --  * Reg 495:      Build configuration info (see router2_core.vhd)
    --  * Reg 496:      ECN/RED control (see router2_ecn_red.vhd)
    --  * Reg 497:      Per-port NAT configuration (see router2_basic_nat.vhd)
    --  * Reg 498:      Gateway configuration (see router2_gateway.vhd)
    --  * Reg 499:      Transmit port-mask (see router2_mailmap.vhd)
    --  * Reg 500:      Transmit offload control (see router2_mailmap.vhd)
    --  * Reg 501-505:  Build-time parameters (see router2_pipeline.vhd)
    --  * Reg 506-507:  Non-IPv4 rule configuration (see router2_noip.vhd)
    --  * Reg 508-509:  CIDR table configuration (see router2_cidr_table.vhd)
    --  * Reg 510:      Interrupt control (see cfgbus_common::cfgbus_interrupt)
    --  * Reg 511:      Received offload control (see router2_mailmap.vhd):
    --  * Reg 512-1023: Port configuration registers (see switch_types.vhd)
    -- ("RT_ADDR_*" prefix avoids conflicts with switch control registers.)
    constant RT_ADDR_TXRX_DAT   : integer := 0;     -- Reg 000 - 399
    constant RT_ADDR_LOGGING    : integer := 489;
    constant RT_ADDR_VLAN_VID   : integer := 490;
    constant RT_ADDR_VLAN_MASK  : integer := 491;
    constant RT_ADDR_VLAN_RATE  : integer := 492;
    constant RT_ADDR_PKT_COUNT  : integer := 493;
    constant RT_ADDR_PORT_SHDN  : integer := 494;
    constant RT_ADDR_INFO       : integer := 495;
    constant RT_ADDR_ECN_RED    : integer := 496;
    constant RT_ADDR_NAT_CTRL   : integer := 497;
    constant RT_ADDR_GATEWAY    : integer := 498;
    constant RT_ADDR_TX_MASK    : integer := 499;
    constant RT_ADDR_TX_CTRL    : integer := 500;
    constant RT_ADDR_PTP_2STEP  : integer := 501;
    constant RT_ADDR_PORT_COUNT : integer := 502;
    constant RT_ADDR_DATA_WIDTH : integer := 503;
    constant RT_ADDR_CORE_CLOCK : integer := 504;
    constant RT_ADDR_TABLE_SIZE : integer := 505;
    constant RT_ADDR_NOIP_DATA  : integer := 506;
    constant RT_ADDR_NOIP_CTRL  : integer := 507;
    constant RT_ADDR_CIDR_DATA  : integer := 508;
    constant RT_ADDR_CIDR_CTRL  : integer := 509;
    constant RT_ADDR_RX_IRQ     : integer := 510;
    constant RT_ADDR_RX_CTRL    : integer := 511;

end package;

package body router2_common is
    function ip_in_subnet(ip1, ip2, mask : ip_addr_t) return boolean is
    begin
        return ((ip1 and mask) = (ip2 and mask));
    end function;

    function ip_is_reserved(ip : ip_addr_t) return boolean is
    begin
        return (ip(31 downto 24) = x"00")   -- Reserved source (0.*.*.*)
            or (ip(31 downto 24) = x"7F");  -- Local loopback (127.*.*.*)
    end function;

    function ip_is_multicast(ip : ip_addr_t) return boolean is
    begin
        return (ip(31 downto 28) = x"E");   -- IP multicast (224-239.*.*.*)
    end function;

    function ip_is_broadcast(ip : ip_addr_t) return boolean is
    begin
        return (ip = IP_BROADCAST);         -- IP broadcast (255.255.255.255)
    end function;

    function ip_prefix2mask(plen : natural) return ip_addr_t is
        variable tmp : ip_addr_t;
    begin
        for n in tmp'range loop
            tmp(n) := bool2bit(plen + n >= 32);
        end loop;
        return tmp;
    end function;

    function ip_checksum(a, b : ip_checksum_t) return ip_checksum_t is
    begin
        if (to_integer(a) + to_integer(b) >= 65536) then
            return a + b + 1;               -- Overflow case
        else
            return a + b;                   -- Normal addition
        end if;
    end function;

    function ip_checksum(a: ip_checksum_t; x: std_logic_vector; bidx: natural := 0) return ip_checksum_t is
        constant bmax : natural := int_max(1, div_ceil(x'length, 8) - 1);
        constant w : positive := div_ceil(x'length + 8*bmax, 16);
        variable y : unsigned(16*w-1 downto 0) := shift_left(resize(unsigned(x), 16*w), 8*bidx);
        variable z : unsigned(31 downto 0) := resize(a, 32);
    begin
        assert(bidx <= bmax) report "bidx (" & natural'image(bidx) & ") > bmax (" & natural'image(bmax) & ")";
        for n in 1 to w loop
            z := z + y(16*n-1 downto 16*n-16);
        end loop;
        return ip_checksum(z(31 downto 16), z(15 downto 0));
    end function;

    function ip_checksum(x : std_logic_vector; bidx: natural := 0) return ip_checksum_t is
        constant CHK_ZERO : ip_checksum_t := (others => '0');
    begin
        return ip_checksum(CHK_ZERO, x, bidx);
    end function;

    function ip_increment(pre, post : std_logic_vector) return ip_checksum_t is
        -- Using the ~m + m' method of RFC1624 Section 3.
        variable x : ip_checksum_t := ip_checksum(not pre);
        variable y : ip_checksum_t := ip_checksum(post);
    begin
        return ip_checksum(x, y);
    end function;

    function get_byte_s(x:std_logic_vector; idx:integer) return byte_t is
        variable tmp : byte_t := (others => '0');
    begin
        if (idx >= 0) then
            tmp := x(8*idx+7 downto 8*idx);
        end if;
        return tmp;
    end function;

    function get_byte_u(x:unsigned; idx:integer) return byte_t is
        variable tmp : byte_t := (others => '0');
    begin
        if (idx >= 0) then
            tmp := std_logic_vector(x(8*idx+7 downto 8*idx));
        end if;
        return tmp;
    end function;

    function get_word_s(x:std_logic_vector; idx:integer) return ip_checksum_t is
        variable tmp : ip_checksum_t := (others => '0');
    begin
        if (idx >= 0) then
            tmp := unsigned(x(16*idx+15 downto 16*idx));
        end if;
        return tmp;
    end function;

    function get_word_u(x:unsigned; idx:integer) return ip_checksum_t is
        variable tmp : ip_checksum_t := (others => '0');
    begin
        if (idx >= 0) then
            tmp := x(16*idx+15 downto 16*idx);
        end if;
        return tmp;
    end function;
end package body;
