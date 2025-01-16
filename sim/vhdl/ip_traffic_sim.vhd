--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Generic IPv4 traffic generator for simulation and test.
--
-- This block generates randomized IPv4 traffic and calculates required
-- header and footer checksums to make valid packets.  User specifies
-- the source and destination indices; the destination IP, source MAC,
-- and source IP simply repeat this index N times.
--
-- In auto-start mode (default), packets are sent continuously.
-- Otherwise, user must request each packet by asserting "pkt_start".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.router2_common.ip_addr_t;
use     work.router_sim_tools.all;
use     work.switch_types.all;

entity ip_traffic_sim is
    generic (
    ROUTER_MAC  : mac_addr_t;               -- Destination MAC
    CLK_DELAY   : time := 0 ns;             -- Delay clock signal
    INIT_SEED1  : positive := 1234;         -- PRNG seed (part 1)
    INIT_SEED2  : positive := 5678;         -- PRNG seed (part 2)
    AUTO_START  : boolean := true);         -- Continuous mode?
    port (
    clk         : in  std_logic;            -- Global clock
    reset_p     : in  std_logic;            -- Global reset
    pkt_start   : in  std_logic := '0';     -- Manual packet start strobe
    pkt_len     : in  integer := -1;        -- Override packet length (bytes)
    pkt_vlan    : in  vlan_hdr_t := VHDR_NONE;  -- Enable VLAN tags?
    idx_dst     : in  unsigned(7 downto 0); -- Destination address (repeat 6x/4x)
    idx_src     : in  unsigned(7 downto 0); -- Source address (repeat 6x/4x)
    out_rate    : in  real := 1.0;          -- Average flow-control rate
    out_port    : out port_rx_m2s;          -- Output data (see switch_types)
    out_bcount  : out natural);             -- Remaining bytes (0 = last)
end ip_traffic_sim;

architecture ip_traffic_sim of ip_traffic_sim is

signal dst_ip       : ip_addr_t;
signal src_ip       : ip_addr_t;
signal src_mac      : mac_addr_t;

signal out_data     : std_logic_vector(7 downto 0) := (others => '0');
signal out_write    : std_logic := '0';
signal out_last     : std_logic := '0';
signal out_bcount_i : natural := 0;

begin

-- Drive each output signal.
out_port.clk        <= clk after CLK_DELAY;
out_port.reset_p    <= reset_p;
out_port.rate       <= get_rate_word(1000);
out_port.status     <= (others => '0');
out_port.tsof       <= TSTAMP_DISABLED;
out_port.tfreq      <= TFREQ_DISABLED;
out_port.rxerr      <= '0';
out_port.data       <= out_data;
out_port.write      <= out_write;
out_port.last       <= out_last;
out_bcount          <= out_bcount_i;

-- Addresses repeat the same byte N times.
dst_ip  <= std_logic_vector(idx_dst & idx_dst & idx_dst & idx_dst);
src_ip  <= std_logic_vector(idx_src & idx_src & idx_src & idx_src);
src_mac <= std_logic_vector(idx_src & idx_src & idx_src & idx_src & idx_src & idx_src);

-- Data generation.
p_src : process(clk)
    -- Packet generator state.
    variable ident      : uint16 := (others => '0');
    variable hdr        : ipv4_header;      -- Header parameters
    variable eth        : eth_packet;       -- Outer packet (Eth)
    variable ip         : ip_packet;        -- Inner packet (IPv4)
    variable pkt_bidx   : natural := 0;     -- Current byte index
    variable pkt_rem    : natural := 0;     -- Remaining bytes
    variable usr_len    : natural := 0;     -- Length of IP data
begin
    if rising_edge(clk) then
        -- Should we begin generating a new packet?
        if (reset_p = '1') then
            pkt_bidx := 0;
            pkt_rem  := 0;
        elsif (pkt_rem = 0 and (AUTO_START or pkt_start = '1')) then
            -- Reset state and choose inner length.
            pkt_bidx := 0;
            if (pkt_len < 0) then           -- Specific length?
                usr_len := rand_int(1480);  -- Random up to MTU
            else
                usr_len := pkt_len;         -- Use specified value
            end if;
            -- Generate the IPv4 header + contents.
            ident := ident + 1;
            hdr := make_ipv4_header(dst_ip, src_ip, ident, IPPROTO_UDP);
            ip  := make_ipv4_pkt(hdr, rand_bytes(usr_len));
            if (pkt_vlan = VHDR_NONE) then
                eth := make_eth_fcs(ROUTER_MAC, src_mac, ETYPE_IPV4, ip.all);
            else
                eth := make_vlan_fcs(ROUTER_MAC, src_mac, pkt_vlan, ETYPE_IPV4, ip.all);
            end if;
            -- Calculate remaining length including all headers.
            pkt_rem := eth.all'length / 8;
        end if;

        -- Generate new data this clock cycle?
        if ((pkt_rem > 0) and (rand_float < out_rate)) then
            -- Determine the next output byte.
            out_data  <= get_packet_bytes(eth.all, pkt_bidx, 1);
            out_last  <= bool2bit(pkt_rem = 1);
            out_write <= '1';
            pkt_bidx  := pkt_bidx + 1;
            pkt_rem   := pkt_rem - 1;
        else
            out_data  <= (others => '0');
            out_last  <= '0';
            out_write <= '0';
        end if;

        -- External copy of remaining bytes counter.
        out_bcount_i <= pkt_rem;
    end if;
end process;

end ip_traffic_sim;
