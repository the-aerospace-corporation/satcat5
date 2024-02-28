--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Address Resolution Protocol (ARP) incoming packet parser
--
-- This block screens incoming packets, looking for valid Address
-- Resolution Protocol frames (IETF RFC 826) of the IPv4-to-Ethernet
-- type.  All other traffic is ignored.
--
-- The output contains the OPER, SHA, SPA, THA, and TPA fields only.
-- Any subsequent padding, including the packet CRC, is stripped.
-- If the input frame is truncated early, the "last" strobe is not
-- asserted and output resumes with the next valid ARP frame. i.e.,
-- Downstream blocks should wait for the "last" strobe and discard
-- all but the last 22 bytes.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity router_arp_parse is
    port (
    -- Network interface (receive only)
    pkt_rx_data     : in  byte_t;
    pkt_rx_last     : in  std_logic;
    pkt_rx_write    : in  std_logic;

    -- Filtered ARP contents (see notes)
    arp_rx_data     : out byte_t;
    arp_rx_first    : out std_logic;
    arp_rx_last     : out std_logic;
    arp_rx_write    : out std_logic;

    -- System clock and reset.
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end router_arp_parse;

architecture router_arp_parse of router_arp_parse is

constant BCOUNT_MAX : byte_u := (others => '1');
signal parse_bcount : byte_u := (others => '0');
signal parse_ignore : std_logic := '0';
signal reg_data     : byte_t := (others => '0');
signal reg_first    : std_logic := '0';
signal reg_last     : std_logic := '0';
signal reg_write    : std_logic := '0';

begin

-- Parse incoming packets, ignoring anything that's not an ARP request.
-- (Note: ARP fields SHA, SPA, TPA, etc. are defined in IETF RFC 826).
p_parse : process(clk)
    variable byte_ok : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Combinational logic: Should we reject this packet?
        --  00-05 = Destination MAC (ignored)
        --  06-11 = Source MAC (ignored)
        --  12-13 = EtherType (Must be 0x0806 = ARP)
        --  14-15 = HTYPE (Must be 1 = Ethernet)
        --  16-17 = PTYPE (Must be 0x0800 = IPv4)
        --  18    = HLEN (Must be 6 bytes)
        --  19    = PLEN (Must be 4 bytes)
        --  20-21 = OPER (Must be 1 or 2)
        --  22-27 = SHA (Sender MAC)
        --  28-31 = SPA (Sender IP)
        --  32-37 = THA (Ignore)
        --  38-41 = TPA (Target IP)
        --  42+   = Ignore CRC and zero-padding beyond this point
        if (parse_bcount = 12) then     -- EtherType (MSB)
            byte_ok := bool2bit(pkt_rx_data = x"08");
        elsif (parse_bcount = 13) then  -- EtherType (LSB)
            byte_ok := bool2bit(pkt_rx_data = x"06");
        elsif (parse_bcount = 14) then  -- HTYPE (MSB)
            byte_ok := bool2bit(pkt_rx_data = x"00");
        elsif (parse_bcount = 15) then  -- HTYPE (LSB)
            byte_ok := bool2bit(pkt_rx_data = x"01");
        elsif (parse_bcount = 16) then  -- PTYPE (MSB)
            byte_ok := bool2bit(pkt_rx_data = x"08");
        elsif (parse_bcount = 17) then  -- PTYPE (LSB)
            byte_ok := bool2bit(pkt_rx_data = x"00");
        elsif (parse_bcount = 18) then  -- HLEN
            byte_ok := bool2bit(pkt_rx_data = x"06");
        elsif (parse_bcount = 19) then  -- PLEN
            byte_ok := bool2bit(pkt_rx_data = x"04");
        elsif (parse_bcount = 20) then  -- OPER (MSB)
            byte_ok := bool2bit(pkt_rx_data = x"00");
        elsif (parse_bcount = 21) then  -- OPER (LSB)
            byte_ok := bool2bit(pkt_rx_data = x"01" or pkt_rx_data = x"02");
        else                            -- Remaining data
            byte_ok := '1';
        end if;

        -- Update parser state machine:
        if (reset_p = '1') then
            parse_ignore <= '0';    -- Global reset
        elsif (pkt_rx_write = '1' and pkt_rx_last = '1') then
            parse_ignore <= '0';    -- Ready for next packet
        elsif (pkt_rx_write = '1' and byte_ok = '0') then
            parse_ignore <= '1';    -- Ignore all subsequent bytes.
        end if;

        -- Count byte offset within each received packet:
        if (reset_p = '1') then
            parse_bcount <= (others => '0');
        elsif (pkt_rx_write = '1' and pkt_rx_last = '1') then
            parse_bcount <= (others => '0');
        elsif (pkt_rx_write = '1' and parse_bcount < BCOUNT_MAX) then
            parse_bcount <= parse_bcount + 1;
        end if;
    end if;
end process;

-- Output registers forward the useful fields only.
p_reg : process(clk)
begin
    if rising_edge(clk) then
        reg_data <= pkt_rx_data;
        if (pkt_rx_write = '1' and parse_ignore = '0') then
            reg_write <= bool2bit(20 <= parse_bcount and parse_bcount <= 41);
            reg_first <= bool2bit(parse_bcount = 20);
            reg_last  <= bool2bit(parse_bcount = 41);
        else
            reg_write <= '0';
            reg_first <= '0';
            reg_last  <= '0';
        end if;
    end if;
end process;

arp_rx_data  <= reg_data;
arp_rx_first <= reg_first;
arp_rx_last  <= reg_last;
arp_rx_write <= reg_write;

end router_arp_parse;
