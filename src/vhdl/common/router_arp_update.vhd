--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Address Resolution Protocol (ARP) interface for updates
--
-- This block handles byte-by-byte implementation of the Address Resolution
-- Protocol (IETF RFC 826) for keeping the local ARP-cache up to date.  The
-- input is a filtered byte stream containing specific ARP fields only
-- (see router_arp_parse); the output is commands for the ARP-cache.
--
-- To reduce duplicate traffic, this block notes MAC/IP pairs from ARP
-- requests (Sender only) and responses (Sender and Target).  In both cases,
-- packets are receive-only; an outgoing network interface is not required.
--
-- To reduce cache overflow, this block includes an optional filter to
-- ignore updates outside the local subnet.  To disable this feature, set
-- SUBNET_INNER = true and subnet_mask = 0.0.0.0, which is the default.
--
-- TODO: Do we need any kind of mitigation against ARP-spoofing attacks?
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;

entity router_arp_update is
    generic (
    -- Match a narrow subnet (inner) or everything else (outer)?
    SUBNET_INNER    : boolean := true);
    port (
    -- Filtered receive interface
    arp_rx_data     : in  byte_t;
    arp_rx_first    : in  std_logic;
    arp_rx_last     : in  std_logic;
    arp_rx_write    : in  std_logic;

    -- Subnet configuration for filtering (optional)
    subnet_addr     : in  ip_addr_t := (others => '0');
    subnet_mask     : in  ip_addr_t := (others => '0');

    -- Update: Write IP/MAC pairs to the cache.
    update_first    : out std_logic;    -- First-byte strobe
    update_addr     : out byte_t;       -- IPv4 then MAC
    update_valid    : out std_logic;
    update_ready    : in  std_logic;

    -- System clock and reset.
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end router_arp_update;

architecture router_arp_update of router_arp_update is

-- Parse useful fields from the input stream.
signal parse_commit : std_logic := '0';
signal parse_ignore : std_logic := '0';
signal parse_oper   : byte_t := (others => '0');
signal parse_sha    : mac_addr_t := (others => '0');
signal parse_spa    : ip_addr_t := (others => '0');
signal parse_tha    : mac_addr_t := (others => '0');
signal parse_tpa    : ip_addr_t := (others => '0');

-- Construct each cache-update command.
signal cmd_state    : integer range 0 to 19 := 0;
signal cmd_busy     : std_logic := '0';
signal cmd_next     : std_logic := '0';
signal cmd_addr     : byte_t := (others => '0');
signal cmd_first    : std_logic := '0';
signal cmd_valid    : std_logic := '0';

begin

-- Parse useful fields from the input stream.
p_parse : process(clk)
    variable sreg : std_logic_vector(167 downto 0) := (others => '0');
begin
    if rising_edge(clk) then
        -- Small state machine to ignore partial frames.
        -- (e.g., Had to discard the first part of a frame while busy.)
        if (reset_p = '1') then
            parse_ignore <= '0';    -- Ready to receive next frame
        elsif (arp_rx_write = '1' and cmd_busy = '1') then
            parse_ignore <= '1';    -- Still busy, discard this frame
        elsif (arp_rx_write = '1' and arp_rx_first = '1') then
            parse_ignore <= '0';    -- Ready to receive next frame
        end if;

        -- Freeze the shift register while command-builder is busy,
        -- otherwise update with each new received byte.
        if (arp_rx_write = '1' and cmd_busy = '0') then
            sreg := sreg(159 downto 0) & arp_rx_data;
            parse_commit <= arp_rx_last and (not parse_ignore);
        else
            parse_commit <= '0';
        end if;

        -- Fields of interest are pulled directly from the big shift register.
        parse_oper <= sreg(167 downto 160);
        parse_sha  <= sreg(159 downto 112);
        parse_spa  <= sreg(111 downto  80);
        parse_tha  <= sreg( 79 downto  32);
        parse_tpa  <= sreg( 31 downto   0);
    end if;
end process;

-- Construct each cache-update command.
cmd_next <= update_ready or not cmd_valid;

p_cmd : process(clk)
    -- Check if the given IP is part of the local subnet, and confirm that
    -- it's not a multicast address (see IETF RFC 1812, Section 3.3.2).
    impure function check_subnet(ip : ip_addr_t; hw : mac_addr_t) return std_logic is
        variable sub : boolean := ip_in_subnet(ip, subnet_addr, subnet_mask);
    begin
        if (ip_is_reserved(ip) or ip_is_multicast(ip) or ip_is_broadcast(ip)) then
            return '0'; -- Block multicast or reserved IP
        elsif (mac_is_broadcast(hw) or mac_is_l2multicast(hw) or mac_is_l3multicast(hw)) then
            return '0'; -- Block multicast MAC address
        else
            return bool2bit(sub xnor SUBNET_INNER);
        end if;
    end function;
    variable clock_en : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Send each byte in the response frame:
        if (parse_commit = '1' or cmd_next = '1') then
            cmd_first <= bool2bit(cmd_state = 0 or cmd_state = 10);
            if (cmd_state < 4) then         -- Sender IP
                cmd_addr <= get_byte_s(parse_spa, 3-cmd_state);
            elsif (cmd_state < 10) then     -- Sender MAC
                cmd_addr <= get_byte_s(parse_sha, 9-cmd_state);
            elsif (cmd_state < 14) then     -- Target IP
                cmd_addr <= get_byte_s(parse_tpa, 13-cmd_state);
            else                            -- Target MAC
                cmd_addr <= get_byte_s(parse_tha, 19-cmd_state);
            end if;
        end if;

        -- Drive VALID flag for the Sender, then Target.
        -- Note: Ignore the junk Target for ARP Requests.
        if (reset_p = '1') then
            cmd_valid <= '0';
        elsif (parse_commit = '1') then
            -- Start of Sender IP/MAC.  Check subnet only.
            cmd_valid <= check_subnet(parse_spa, parse_sha);
        elsif (cmd_state = 10 and cmd_next = '1') then
            -- Start of Target IP/MAC.  Check subnet and command type.
            cmd_valid <= check_subnet(parse_tpa, parse_tha)
                     and bool2bit(parse_oper = x"02");
        elsif (cmd_state = 0 and cmd_next = '1') then
            -- End of Target IP/MAC, revert to idle.
            cmd_valid <= '0';
        end if;

        -- Data-valid flag is set by the commit strobe, then held high
        -- until the next downstream block accepts the final byte.
        if (reset_p = '1') then
            cmd_busy <= '0';
        elsif (parse_commit = '1') then
            cmd_busy <= '1';
        elsif (cmd_state = 0 and cmd_next = '1') then
            cmd_busy <= '0';
        end if;

        -- State counter is the byte offset for the NEXT byte to be sent.
        -- Increment it as soon as we've latched each value, above.
        if (reset_p = '1') then
            cmd_state <= 0;       -- Reset to idle state.
        elsif ((parse_commit = '1') or (cmd_state > 0 and cmd_next = '1')) then
            if (cmd_state = 19) then
                cmd_state <= 0;   -- Done, revert to idle.
            else
                cmd_state <= cmd_state + 1;
            end if;
        end if;
    end if;
end process;

update_first <= cmd_first;
update_addr  <= cmd_addr;
update_valid <= cmd_valid;

end router_arp_update;
