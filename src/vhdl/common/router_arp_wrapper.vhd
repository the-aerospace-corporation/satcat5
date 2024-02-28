--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Proxy-ARP wrapper
--
-- This block encapsulates all functions required for Proxy-ARP:
--   * Cache for local MAC addresses (router_arp_cache)
--   * MAC-replacement to route incoming frames (router_mac_replace)
--   * Filter for incoming ARP messages (router_arp_parse).
--   * Writing updates to the cache (router_arp_update)
--   * Replying to ARP queries (router_arp_proxy)
--   * Combining all outputs into a single byte stream (packet_inject)
--
-- Inputs are received data streams from the local subnet (eavesdropping
-- mode with no flow control) and the remote subnet (AXI flow control).
--
-- Output is the combined packet stream back to the local subnet, and
-- an auxiliary ICMP stream going to the remote subnet.
--
-- All inputs and outputs should be Ethernet frames with the FCS removed.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;

entity router_arp_wrapper is
    generic (
    -- MAC address for this router
    ROUTER_MACADDR  : mac_addr_t;
    -- Subnet type for the Proxy-ARP function
    PROXY_SUB_INNER : boolean;
    -- Rules for incoming packets (see router_mac_replace)
    RETRY_KBYTES    : natural := 4;
    RETRY_DLY_CLKS  : natural := 1_000_000;
    NOIP_BLOCK_ALL  : boolean := true;
    -- ICMP buffer and ID parameters.
    ICMP_ECHO_BYTES : natural := 64;
    ICMP_REPLY_TTL  : natural := 64;
    ICMP_ID_INIT    : natural := 0;
    ICMP_ID_INCR    : natural := 1;
    -- Size of the ARP cache
    ARP_CACHE_SIZE  : positive := 32);
    port (
    -- Local network port.
    lcl_rx_data     : in  byte_t;
    lcl_rx_last     : in  std_logic;
    lcl_rx_write    : in  std_logic;
    lcl_tx_data     : out byte_t;
    lcl_tx_last     : out std_logic;
    lcl_tx_valid    : out std_logic;
    lcl_tx_ready    : in  std_logic;

    -- Remote network port.
    net_rx_data     : in  byte_t;
    net_rx_last     : in  std_logic;
    net_rx_valid    : in  std_logic;
    net_rx_ready    : out std_logic;
    net_rx_error    : out std_logic;
    net_tx_data     : out byte_t;
    net_tx_last     : out std_logic;
    net_tx_valid    : out std_logic;
    net_tx_ready    : in  std_logic;

    -- Proxy subnet configuration.
    proxy_ip_addr   : in  ip_addr_t;
    proxy_sub_addr  : in  ip_addr_t;
    proxy_sub_mask  : in  ip_addr_t;

    -- Dropped-packet strobe.
    pkt_dropped     : out std_logic;

    -- System clock and reset.
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end router_arp_wrapper;

architecture router_arp_wrapper of router_arp_wrapper is

-- Filter the incoming network stream for ARP messages.
signal arp_rx_data      : byte_t;
signal arp_rx_first     : std_logic;
signal arp_rx_last      : std_logic;
signal arp_rx_write     : std_logic;

-- Control streams for the ARP cache
signal query_first      : std_logic;    -- First-byte strobe
signal query_addr       : byte_t;       -- IPv4 address
signal query_valid      : std_logic;
signal query_ready      : std_logic;
signal reply_first      : std_logic;    -- First-byte strobe
signal reply_match      : std_logic;    -- Entry in table?
signal reply_addr       : byte_t;       -- MAC address
signal reply_write      : std_logic;
signal request_first    : std_logic;    -- First-byte strobe
signal request_addr     : byte_t;       -- IPv4 address
signal request_write    : std_logic;
signal update_first     : std_logic;    -- First-byte strobe
signal update_addr      : byte_t;       -- IPv4 then MAC
signal update_valid     : std_logic;
signal update_ready     : std_logic;

-- Combine each of the output streams.
-- (Note: Lower index = Higher priority)
constant COMBINE_STREAMS : integer := 3;
signal combine_data     : byte_array_t(COMBINE_STREAMS-1 downto 0);
signal combine_last     : std_logic_vector(COMBINE_STREAMS-1 downto 0);
signal combine_valid    : std_logic_vector(COMBINE_STREAMS-1 downto 0);
signal combine_ready    : std_logic_vector(COMBINE_STREAMS-1 downto 0);
signal combine_error    : std_logic;
signal repl_error       : std_logic;

begin

-- Consolidate packet-dropped and error strobes.
net_rx_error <= combine_error or repl_error;

-- Filter the incoming network stream for ARP messages.
u_parse : entity work.router_arp_parse
    port map(
    pkt_rx_data     => lcl_rx_data,
    pkt_rx_last     => lcl_rx_last,
    pkt_rx_write    => lcl_rx_write,
    arp_rx_data     => arp_rx_data,
    arp_rx_first    => arp_rx_first,
    arp_rx_last     => arp_rx_last,
    arp_rx_write    => arp_rx_write,
    clk             => clk,
    reset_p         => reset_p);

u_update : entity work.router_arp_update
    port map(
    arp_rx_data     => arp_rx_data,
    arp_rx_first    => arp_rx_first,
    arp_rx_last     => arp_rx_last,
    arp_rx_write    => arp_rx_write,
    update_first    => update_first,
    update_addr     => update_addr,
    update_valid    => update_valid,
    update_ready    => update_ready,
    clk             => clk,
    reset_p         => reset_p);

u_proxy : entity work.router_arp_proxy
    generic map(
    SUBNET_INNER    => PROXY_SUB_INNER,
    LOCAL_MACADDR   => ROUTER_MACADDR)
    port map(
    arp_rx_data     => arp_rx_data,
    arp_rx_first    => arp_rx_first,
    arp_rx_last     => arp_rx_last,
    arp_rx_write    => arp_rx_write,
    pkt_tx_data     => combine_data(2),
    pkt_tx_last     => combine_last(2),
    pkt_tx_valid    => combine_valid(2),
    pkt_tx_ready    => combine_ready(2),
    router_addr     => proxy_ip_addr,
    subnet_addr     => proxy_sub_addr,
    subnet_mask     => proxy_sub_mask,
    clk             => clk,
    reset_p         => reset_p);

-- Issue ARP requests for each cache miss.
u_request : entity work.router_arp_request
    generic map(
    LOCAL_MACADDR   => ROUTER_MACADDR)
    port map(
    pkt_tx_data     => combine_data(1),
    pkt_tx_last     => combine_last(1),
    pkt_tx_valid    => combine_valid(1),
    pkt_tx_ready    => combine_ready(1),
    request_first   => request_first,
    request_addr    => request_addr,
    request_write   => request_write,
    router_ipaddr   => proxy_ip_addr,
    clk             => clk,
    reset_p         => reset_p);

-- ARP cache
u_cache : entity work.router_arp_cache
    generic map(
    TABLE_SIZE      => ARP_CACHE_SIZE)
    port map(
    query_first     => query_first,
    query_addr      => query_addr,
    query_valid     => query_valid,
    query_ready     => query_ready,
    reply_first     => reply_first,
    reply_match     => reply_match,
    reply_addr      => reply_addr,
    reply_write     => reply_write,
    request_first   => request_first,
    request_addr    => request_addr,
    request_write   => request_write,
    update_first    => update_first,
    update_addr     => update_addr,
    update_valid    => update_valid,
    update_ready    => update_ready,
    clk             => clk,
    reset_p         => reset_p);

-- The MAC-replacement engine
u_replace : entity work.router_mac_replace
    generic map(
    ROUTER_MACADDR  => ROUTER_MACADDR,
    RETRY_KBYTES    => RETRY_KBYTES,
    RETRY_DLY_CLKS  => RETRY_DLY_CLKS,
    NOIP_BLOCK_ALL  => NOIP_BLOCK_ALL,
    ICMP_ECHO_BYTES => ICMP_ECHO_BYTES,
    ICMP_REPLY_TTL  => ICMP_REPLY_TTL,
    ICMP_ID_INIT    => ICMP_ID_INIT,
    ICMP_ID_INCR    => ICMP_ID_INCR)
    port map(
    in_data         => net_rx_data,
    in_last         => net_rx_last,
    in_valid        => net_rx_valid,
    in_ready        => net_rx_ready,
    out_data        => combine_data(0),
    out_last        => combine_last(0),
    out_valid       => combine_valid(0),
    out_ready       => combine_ready(0),
    icmp_data       => net_tx_data,
    icmp_last       => net_tx_last,
    icmp_valid      => net_tx_valid,
    icmp_ready      => net_tx_ready,
    query_addr      => query_addr,
    query_first     => query_first,
    query_valid     => query_valid,
    query_ready     => query_ready,
    reply_addr      => reply_addr,
    reply_first     => reply_first,
    reply_match     => reply_match,
    reply_write     => reply_write,
    router_ipaddr   => proxy_ip_addr,
    pkt_drop        => pkt_dropped,
    pkt_error       => repl_error,
    clk             => clk,
    reset_p         => reset_p);

-- Combine each of the output streams.
u_combine : entity work.packet_inject
    generic map(
    INPUT_COUNT     => COMBINE_STREAMS,
    APPEND_FCS      => false)
    port map(
    in0_data        => combine_data(0),
    in1_data        => combine_data(1),
    in2_data        => combine_data(2),
    in_last         => combine_last,
    in_valid        => combine_valid,
    in_ready        => combine_ready,
    in_error        => combine_error,
    out_data        => lcl_tx_data,
    out_last        => lcl_tx_last,
    out_valid       => lcl_tx_valid,
    out_ready       => lcl_tx_ready,
    clk             => clk,
    reset_p         => reset_p);

end router_arp_wrapper;
