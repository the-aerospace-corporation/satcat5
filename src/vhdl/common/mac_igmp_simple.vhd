--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Simplified MAC-layer IGMP snooping
--
-- Multicasting allows one host to send the same packet to many other
-- endpoints.  The Internet Group Management Protocol (IGMP) allows hosts
-- and adjacent routers to establish IPv4 multicast groups/subscriptions,
-- to efficiently route such traffic.
--
-- At the link layer, IPv4 multicast traffic uses the reserved MAC address
-- range 01:00:5e:*:*:*.  The simplest option is to treat all multicast traffic
-- as broadcast traffic; this is functional but inefficient.  More advanced
-- switches can "snoop" on IGMP exchanges to determine which traffic must be
-- sent to which port(s).
--
-- A full-featured implementation must track the group membership for a large
-- number of addresses on each port.  However, this greatly raises complexity.
-- This block implements a much simpler compromise: multicast traffic is
-- forwarded to any port that has subscribed to ANY multicast group, regardless
-- of addresses.
--
-- This block is meant to work directly alongside the MAC-lookup block:
--  * Accept a stream of Ethernet frames with any bus width (8-infinity)
--  * Watch for IGMP traffic to determine which port(s) are IGMP-aware.
--  * Watch for multicast frames and assert the appropriate destination
--    strobe(s), on a frame-by-frame basis.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity mac_igmp_simple is
    generic (
    IO_BYTES        : positive;         -- Width of main data port
    PORT_COUNT      : positive;         -- Number of Ethernet ports
    IGMP_TIMEOUT    : positive := 63);  -- Timeout for stale entries
    port (
    -- Main input (Ethernet frame) does not require flow-control.
    -- PSRC is the input port-mask and must be held for the full frame.
    in_psrc         : in  integer range 0 to PORT_COUNT-1;
    in_wcount       : in  mac_bcount_t;
    in_data         : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_last         : in  std_logic;
    in_write        : in  std_logic;

    -- Search result is the port mask for the destination port(s).
    -- It is asserted only for broadcast and multicast frames.
    out_pdst        : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_valid       : out std_logic;
    out_ready       : in  std_logic;
    out_error       : out std_logic;

    -- Promiscuous-port mask (optional)
    cfg_prmask      : in  std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');

    -- Scrub interface (typically ~1Hz, for IGMP timeouts)
    scrub_req       : in  std_logic;

    -- System interface
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_igmp_simple;

architecture mac_igmp_simple of mac_igmp_simple is

subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);

-- IGMP snooping and per-port timeouts.
signal igmp_det     : port_mask_t := (others => '0');
signal igmp_mask    : port_mask_t := (others => '0');

-- Detection of multicast frames.
signal frm_pdst     : port_mask_t := (others => '0');
signal frm_wr       : std_logic := '0';

begin

-- IGMP snooping: Assert DET strobe for any IGMP "Report" datagrams.
-- Note: Check IP header fields, but don't bother with checksum.
p_snoop : process(clk)
    variable etype_ipv4m    : std_logic := '0'; -- EtherType MSBs
    variable etype_ipv4l    : std_logic := '0'; -- EtherType LSBs
    variable data_start     : integer range IP_HDR_VERSION to IP_HDR_MAX := IP_HDR_MAX;
    variable iphdr_ipv4     : std_logic := '0'; -- IP-header Version
    variable iphdr_proto    : std_logic := '0'; -- IP-header Protocol
    variable igmp_type      : std_logic := '0'; -- IGMP Type field
    variable snoop_rdy      : std_logic := '0'; -- End-of-frame
    variable snoop_idx      : integer range 0 to PORT_COUNT-1 := 0;
    variable temp           : byte_t := (others => '0');
    variable temph, templ   : nybb_u := (others => '0');
begin
    if rising_edge(clk) then
        -- If we've received all elements of a valid IGMP Report,
        -- assert the "detect" strobe on the currently active port.
        if (reset_p = '1' or snoop_rdy = '0') then
            igmp_det <= (others => '0');
        else
            for n in igmp_det'range loop
                igmp_det(n) <= bool2bit(n = snoop_idx) and
                    etype_ipv4m and etype_ipv4l and
                    iphdr_ipv4 and iphdr_proto and igmp_type;
            end loop;
        end if;

        -- Confirm each field as it passes through on the main stream.
        -- (Depending on bus width, these might happen in sequence or all at once.)
        if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+0, in_wcount)) then
            temp := strm_byte_value(IO_BYTES, ETH_HDR_ETYPE+0, in_data);
            etype_ipv4m := bool2bit(temp = x"08");  -- Etype = IPv4 (0x0800)
        end if;
        if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+1, in_wcount)) then
            temp := strm_byte_value(IO_BYTES, ETH_HDR_ETYPE+1, in_data);
            etype_ipv4l := bool2bit(temp = x"00");  -- Etype = IPv4 (0x0800)
        end if;
        if (in_write = '1' and strm_byte_present(IO_BYTES, IP_HDR_VERSION, in_wcount)) then
            temp    := strm_byte_value(IO_BYTES, IP_HDR_VERSION, in_data);
            temph   := unsigned(temp(7 downto 4));  -- Version (Expect IPv4 = 0x4)
            templ   := unsigned(temp(3 downto 0));  -- Header length = 5-15 words
            data_start  := IP_HDR_DATA(templ);      -- Location for start of data?
            iphdr_ipv4  := bool2bit(temph = 4 and templ >= 5);  -- Valid IPv4 header?
        end if;
        if (in_write = '1' and strm_byte_present(IO_BYTES, IP_HDR_PROTOCOL, in_wcount)) then
            temp := strm_byte_value(IO_BYTES, IP_HDR_PROTOCOL, in_data);
            iphdr_proto := bool2bit(temp = x"02");  -- IP-Protocol = IGMP (0x02)
        end if;
        if (in_write = '1' and strm_byte_present(IO_BYTES, data_start, in_wcount)) then
            temp := strm_byte_value(IO_BYTES, data_start, in_data);
            igmp_type := bool2bit(temp = x"12")     -- IGMPv1 Report
                      or bool2bit(temp = x"16")     -- IGMPv2 Report
                      or bool2bit(temp = x"22");    -- IGMPv3 Report
            snoop_idx := in_psrc;                   -- Latch input port index
            snoop_rdy := not reset_p;               -- Last byte we care about
        else
            snoop_rdy := '0';
        end if;
    end if;
end process;

-- Per-port timeouts.
gen_timeout : for n in igmp_det'range generate
    p_timeout : process(clk)
        variable count : integer range 0 to IGMP_TIMEOUT := 0;
    begin
        if rising_edge(clk) then
            igmp_mask(n) <= bool2bit(count > 0);
            if (reset_p = '1') then
                count := 0;             -- Global reset
            elsif (igmp_det(n) = '1') then
                count := IGMP_TIMEOUT;  -- IGMP-Report detected
            elsif (scrub_req = '1' and count > 0) then
                count := count - 1;     -- Countdown each scrub tick
            end if;
        end if;
    end process;
end generate;

-- Detection of multicast frames.
p_multi : process(clk)
    variable mac_dst    : mac_addr_t := (others => '0');
    variable mac_rdy    : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Check if destination MAC is broadcast or multicast.
        -- Note: This mask will bitwise-AND with the one from "mac_lookup".
        if (mac_rdy = '1') then
            if (mac_is_l3multicast(mac_dst)) then
                -- Multicast to IGMP-aware or promiscuous ports only.
                frm_pdst <= igmp_mask or cfg_prmask;
            else
                -- In all other cases, let regular lookup handle it.
                frm_pdst <= (others => '1');
            end if;
        end if;
        frm_wr <= mac_rdy and not reset_p;

        -- Latch each byte of the destination MAC.
        -- (As above, odd structure is so we can handle arbitrary input widths.)
        for n in 0 to 5 loop
            if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_DSTMAC+n, in_wcount)) then
                mac_dst(47-8*n downto 40-8*n) := strm_byte_value(IO_BYTES, ETH_HDR_DSTMAC+n, in_data);
            end if;
        end loop;
        -- Destination MAC is the only field we care about.
        mac_rdy := (not reset_p) and in_write and bool2bit(
            strm_byte_present(IO_BYTES, ETH_HDR_DSTMAC+5, in_wcount));
    end if;
end process;

-- Small FIFO for output flow-control.
u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => PORT_COUNT,
    DEPTH_LOG2  => 4)
    port map(
    in_data     => frm_pdst,
    in_write    => frm_wr,
    out_data    => out_pdst,
    out_valid   => out_valid,
    out_read    => out_ready,
    fifo_error  => out_error,
    clk         => clk,
    reset_p     => reset_p);

end mac_igmp_simple;
