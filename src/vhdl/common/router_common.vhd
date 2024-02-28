--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Package definition: Useful constants and functions for router_xx blocks
--
-- This package define a variety constants and functions for manipulating
-- Ethernet and IPv4 frames, to maximize code reuse among various blocks.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

package router_common is
    -- IPv4 address (or subnet mask, etc.) is 32 bits long.
    subtype ip_addr_t is std_logic_vector(31 downto 0);
    constant IP_NOT_VALID : ip_addr_t := (others => '0');
    constant IP_BROADCAST : ip_addr_t := (others => '1');

    -- Functions for checking special IP addresses:
    function ip_in_subnet(ip1, ip2, mask : ip_addr_t) return boolean;
    function ip_is_reserved(ip : ip_addr_t) return boolean;
    function ip_is_multicast(ip : ip_addr_t) return boolean;
    function ip_is_broadcast(ip : ip_addr_t) return boolean;

    -- One's complement sum with carry for verifying IPv4 checksum.
    -- (IETF RFC 1071: "Computing the Internet Checksum")
    subtype ip_checksum_t is unsigned(15 downto 0);
    function ip_checksum(a, b : ip_checksum_t) return ip_checksum_t;

    -- Use 16-bit counters for Ethernet frame lengths.
    subtype bcount_t is unsigned(15 downto 0);
    constant BCOUNT_MAX : bcount_t := (others => '1');

    -- Timestamps are a 32-bit unsigned millisecond counter.
    -- (Ideally referenced to UTC midmight, but arbitrary is OK.)
    subtype timestamp_t is unsigned(31 downto 0);

    -- Get the Nth byte or word from a longer vector, counting from LSB.
    function get_byte_s(x:std_logic_vector; idx:integer) return byte_t;
    function get_byte_u(x:unsigned; idx:integer) return byte_t;
    function get_word_s(x:std_logic_vector; idx:integer) return ip_checksum_t;
    function get_word_u(x:unsigned; idx:integer) return ip_checksum_t;

    -- Define internal codes for packet-forwarding decisions:
    constant ACT_WIDTH      : integer := 4;
    subtype action_t is std_logic_vector(ACT_WIDTH-1 downto 0);
    constant ACT_DROP       : action_t := i2s( 0, ACT_WIDTH);   -- Silently drop frame
    constant ACT_FWD_RAW    : action_t := i2s( 1, ACT_WIDTH);   -- Forward non-IP frame
    constant ACT_FWD_IP0    : action_t := i2s( 2, ACT_WIDTH);   -- Forward IP-frame (Chk carry 0)
    constant ACT_FWD_IP1    : action_t := i2s( 3, ACT_WIDTH);   -- Forward IP-frame (Chk carry 1)
    constant ACT_ICMP_ECHO  : action_t := i2s( 4, ACT_WIDTH);   -- Echo reply
    constant ACT_ICMP_DNU   : action_t := i2s( 5, ACT_WIDTH);   -- Destination network unreachable
    constant ACT_ICMP_DHU   : action_t := i2s( 6, ACT_WIDTH);   -- Destination host unreachable
    constant ACT_ICMP_DRU   : action_t := i2s( 7, ACT_WIDTH);   -- Destination protocol unreachable
    constant ACT_ICMP_DPU   : action_t := i2s( 8, ACT_WIDTH);   -- Destination port unreachable
    constant ACT_ICMP_TTL   : action_t := i2s( 9, ACT_WIDTH);   -- Time exceeded
    constant ACT_ICMP_TIME  : action_t := i2s(10, ACT_WIDTH);   -- Timestamp reply
    constant ACT_ICMP_MASK  : action_t := i2s(11, ACT_WIDTH);   -- Address mask reply
end package;

package body router_common is
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

    function ip_checksum(a, b : ip_checksum_t) return ip_checksum_t is
    begin
        if (to_integer(a) + to_integer(b) >= 65536) then
            return a + b + 1;               -- Overflow case
        else
            return a + b;                   -- Normal addition
        end if;
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
