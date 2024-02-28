--------------------------------------------------------------------------
-- Copyright 2020-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Top-level for IP router, configured to act inline with a switch port
--
-- This block is a high-level wrapper that implements an IPv4 router.
-- It is designed to use the switch_core's "port" interface, so that it
-- can be used inline with any of the usual port types.  The local subnet
-- is attached to the switch_core, and implements an ARP-Proxy to replace
-- the MAC-address of incoming frames.  The remote subnet is then attached
-- to the external interface block (e.g., port_rgmii, port_rmii, etc.).
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.switch_types.all;

entity router_inline_top is
    generic (
    -- MAC address for the router itself
    ROUTER_MACADDR      : mac_addr_t;
    -- Is the specified subnet on the NET or LCL port?
    SUBNET_IS_LCL_PORT  : boolean;
    -- ARP-Proxy and MAC-replacement policy
    PROXY_EN_EGRESS     : boolean := true;
    PROXY_EN_INGRESS    : boolean := true;
    PROXY_RETRY_KBYTES  : natural := 4;
    PROXY_RETRY_DELAY   : natural := 1_000_000;
    PROXY_CACHE_SIZE    : natural := 32;
    -- ICMP buffer and ID parameters.
    ICMP_ECHO_BYTES     : natural := 64;
    ICMP_REPLY_TTL      : natural := 64;
    -- Policy for IPv4 packets
    IPV4_BLOCK_MCAST    : boolean := true;  -- Block IPv4 multicast?
    IPV4_BLOCK_FRAGMENT : boolean := true;  -- Block fragmented frames?
    IPV4_DMAC_FILTER    : boolean := true;  -- Destination MAC must be router?
    IPV4_DMAC_REPLACE   : boolean := true;  -- Replace destination MAC in output?
    IPV4_SMAC_REPLACE   : boolean := true;  -- Replace source MAC in output?
    -- Policy for non-IPv4 packets
    NOIP_BLOCK_ALL      : boolean := true;  -- Block all non-IP?
    NOIP_BLOCK_ARP      : boolean := true;  -- Block all ARP frames?
    NOIP_BLOCK_BCAST    : boolean := true;  -- Block non-IP broadcast?
    NOIP_DMAC_REPLACE   : boolean := true;  -- Replace destination MAC in output?
    NOIP_SMAC_REPLACE   : boolean := true;  -- Replace source MAC in output?
    -- Minimum and maximum frame-size on each subnet.
    LCL_FRAME_BYTES_MIN : natural := MIN_FRAME_BYTES;
    NET_FRAME_BYTES_MIN : natural := MIN_FRAME_BYTES);
    port (
    -- Local switch port.
    lcl_rx_data         : out port_rx_m2s;  -- Ingress data out
    lcl_tx_data         : in  port_tx_s2m;  -- Egress data in
    lcl_tx_ctrl         : out port_tx_m2s;

    -- Remote network port.
    net_rx_data         : in  port_rx_m2s;  -- Ingress data in
    net_tx_data         : out port_tx_s2m;  -- Egress data out
    net_tx_ctrl         : in  port_tx_m2s;

    -- Router subnet configuration.
    -- TODO: Replace this with a true FIB table.
    router_ip_addr      : in  ip_addr_t;
    router_sub_addr     : in  ip_addr_t;
    router_sub_mask     : in  ip_addr_t;
    router_time_msec    : in  timestamp_t;

    -- Fixed destination for IPv4 packets on each subnet, if enabled.
    -- Do not use the broadcast address, per RFC 1812 section 4.2.3.1.
    -- (Only used if PROXY_EN_* = false and IPV4_DMAC_REPLACE = true)
    ipv4_dmac_egress    : in  mac_addr_t := x"DEADBEEFCAFE";
    ipv4_dmac_ingress   : in  mac_addr_t := x"DEADBEEFCAFE";

    -- Fixed destination for non-IPv4 packets on each subnet, if enabled.
    -- (Only used if NOIP_BLOCK_ALL = false and NOIP_DMAC_REPLACE = true)
    noip_dmac_egress    : in  mac_addr_t := (others => '1');
    noip_dmac_ingress   : in  mac_addr_t := (others => '1');

    -- Dropped-packet statistics.
    router_drop_clk     : out std_logic;
    router_drop_count   : out bcount_t;

    -- System reset (optional)
    ext_reset_p         : in  std_logic := '0');
end router_inline_top;

architecture router_inline_top of router_inline_top is

-- Internal clock and reset.
signal clk_main         : std_logic;
signal reset_async      : std_logic;
signal reset_p          : std_logic;
signal link_ok          : std_logic;

-- FIFO for ingress data.
-- (Note: These signals are in a separate clock domain.)
signal inraw_clk        : std_logic;
signal inraw_data       : byte_t;
signal inraw_last       : std_logic;
signal inraw_write      : std_logic;
signal inraw_error      : std_logic;
signal inbuf_data       : byte_t;
signal inbuf_write      : std_logic;
signal inbuf_commit     : std_logic;
signal inbuf_revert     : std_logic;
signal inbuf_error      : std_logic;

-- Ingress datapath
signal ig_inbuf         : axi_stream8;
signal ig_inbuf_write   : std_logic;
signal ig_gate          : axi_stream8;
signal ig_proxy         : axi_stream8;
signal ig_out           : axi_stream8;

-- Egress datapath
signal eg_inraw         : axi_stream8;
signal eg_nocrc         : axi_stream8;
signal eg_nocrc_write   : std_logic;
signal eg_gate          : axi_stream8;
signal eg_proxy         : axi_stream8;
signal eg_out           : axi_stream8;

-- Auxiliary data (ICMP)
signal aux_ig_proxy     : axi_stream8;
signal aux_ig_gate      : axi_stream8;
signal aux_eg_proxy     : axi_stream8;
signal aux_eg_gate      : axi_stream8;

-- Count dropped packets.
signal dropped_pkts     : bcount_t := (others => '0');
signal drop_ig_ovr      : std_logic;
signal drop_ig_crc      : std_logic;
signal drop_ig_gate     : std_logic;
signal drop_ig_repl     : std_logic;
signal drop_eg_gate     : std_logic;
signal drop_eg_repl     : std_logic;

-- Consolidate error strobes.
signal error_combined   : std_logic := '0';
signal error_inbuf      : std_logic;
signal error_ig_proxy   : std_logic;
signal error_ig_out     : std_logic;
signal error_eg_proxy   : std_logic;
signal error_eg_out     : std_logic;

begin

-- Break out the port signals:
lcl_rx_data.clk     <= clk_main;
lcl_rx_data.data    <= ig_out.data;
lcl_rx_data.last    <= ig_out.last;
lcl_rx_data.write   <= ig_out.valid;
lcl_rx_data.rxerr   <= error_combined;
lcl_rx_data.rate    <= net_rx_data.rate;
lcl_rx_data.status  <= net_rx_data.status;
lcl_rx_data.tsof    <= net_tx_ctrl.tnow;
lcl_rx_data.reset_p <= reset_p;
ig_out.ready        <= '1';

lcl_tx_ctrl.clk     <= clk_main;
lcl_tx_ctrl.pstart  <= '1'; -- PTP not supported
lcl_tx_ctrl.tnow    <= net_tx_ctrl.tnow;
lcl_tx_ctrl.txerr   <= net_tx_ctrl.txerr;
lcl_tx_ctrl.reset_p <= reset_p;
lcl_tx_ctrl.ready   <= eg_inraw.ready;
eg_inraw.data       <= lcl_tx_data.data;
eg_inraw.last       <= lcl_tx_data.last;
eg_inraw.valid      <= lcl_tx_data.valid;

inraw_clk           <= net_rx_data.clk;
inraw_data          <= net_rx_data.data;
inraw_last          <= net_rx_data.last;
inraw_write         <= net_rx_data.write;
inraw_error         <= net_rx_data.rxerr;

net_tx_data.data    <= eg_out.data;
net_tx_data.last    <= eg_out.last;
net_tx_data.valid   <= eg_out.valid;
eg_out.ready        <= net_tx_ctrl.ready;
clk_main            <= net_tx_ctrl.clk;

-- Synchronize the master reset signal.
reset_async <= net_rx_data.reset_p or net_tx_ctrl.reset_p or ext_reset_p;

u_reset : sync_reset
    port map(
    in_reset_p  => reset_async,
    out_reset_p => reset_p,
    out_clk     => clk_main);

-- Synchronize the "link-OK" flag and various error strobes.
u_link_ok : sync_buffer
    port map(
    in_flag     => '1',
    out_flag    => link_ok,
    out_clk     => clk_main,
    reset_p     => reset_p);

u_port_error : sync_pulse2pulse
    port map(
    in_strobe   => inraw_error,
    in_clk      => inraw_clk,
    out_strobe  => error_inbuf,
    out_clk     => clk_main,
    reset_p     => reset_p);

u_inbuf_crc : sync_pulse2pulse
    port map(
    in_strobe   => inbuf_error,
    in_clk      => inraw_clk,
    out_strobe  => drop_ig_crc,
    out_clk     => clk_main,
    reset_p     => reset_p);

-- Consolidate dropped-packet and error strobes.
p_dropct : process(clk_main)
    variable incr : integer range 0 to 5 := 0;
begin
    if rising_edge(clk_main) then
        -- Count all dropped packets. (Recommended practice per RFC-1812.)
        incr := u2i(drop_ig_ovr)
              + u2i(drop_ig_crc)
              + u2i(drop_ig_gate)
              + u2i(drop_ig_repl)
              + u2i(drop_eg_repl)
              + u2i(drop_eg_gate);
        if (reset_p = '1') then
            dropped_pkts <= (others => '0');
        else
            dropped_pkts <= dropped_pkts + incr;
        end if;

        -- Combined error strobe. (Often used as reset, high fanout.)
        if (reset_p = '1') then
            error_combined <= '0';
        else
            error_combined <= error_inbuf
                           or error_ig_proxy or error_eg_proxy
                           or error_ig_out or error_eg_out;
        end if;
    end if;
end process;

router_drop_clk     <= clk_main;
router_drop_count   <= dropped_pkts;

-----------------------------------------------------------
-- Ingress datapath
-----------------------------------------------------------

-- Note: ICMP messages are sent by ip_gateway and arp_wrapper blocks, but
--       they don't coordinate their IP-ID counters.  To reduce collisions,
--       split even and odd by manipulating the INIT/INCR settings.

-- Check incoming frames and strip CRC.
u_crc : entity work.eth_frame_check
    generic map(
    ALLOW_RUNT      => true,
    STRIP_FCS       => true)
    port map(
    in_data         => inraw_data,
    in_last         => inraw_last,
    in_write        => inraw_write,
    out_data        => inbuf_data,
    out_write       => inbuf_write,
    out_commit      => inbuf_commit,
    out_revert      => inbuf_revert,
    out_error       => inbuf_error,
    clk             => inraw_clk,
    reset_p         => net_rx_data.reset_p);

-- Packet buffer is required for CRC check, and allows clock transition.
-- It only needs to handle a single max-size packet (~1500 bytes)
u_inbuf : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => 1,
    OUTPUT_BYTES    => 1,
    BUFFER_KBYTES   => 2)
    port map(
    in_clk          => inraw_clk,
    in_data         => inbuf_data,
    in_last_commit  => inbuf_commit,
    in_last_revert  => inbuf_revert,
    in_write        => inbuf_write,
    in_overflow     => open,
    out_clk         => clk_main,
    out_data        => ig_inbuf.data,
    out_last        => ig_inbuf.last,
    out_valid       => ig_inbuf.valid,
    out_ready       => ig_inbuf.ready,
    out_overflow    => drop_ig_ovr,
    reset_p         => reset_p);

-- Ingress IP gateway
u_ig_gate : entity work.router_ip_gateway
    generic map(
    ROUTER_MACADDR      => ROUTER_MACADDR,
    IPV4_BLOCK_MCAST    => IPV4_BLOCK_MCAST,
    IPV4_BLOCK_FRAGMENT => IPV4_BLOCK_FRAGMENT,
    IPV4_DMAC_FILTER    => IPV4_DMAC_FILTER,
    IPV4_DMAC_REPLACE   => IPV4_DMAC_REPLACE,
    IPV4_SMAC_REPLACE   => IPV4_SMAC_REPLACE,
    NOIP_BLOCK_ALL      => NOIP_BLOCK_ALL,
    NOIP_BLOCK_ARP      => NOIP_BLOCK_ARP,
    NOIP_BLOCK_BCAST    => NOIP_BLOCK_BCAST,
    NOIP_DMAC_REPLACE   => NOIP_DMAC_REPLACE,
    NOIP_SMAC_REPLACE   => NOIP_SMAC_REPLACE,
    ICMP_ECHO_BYTES     => ICMP_ECHO_BYTES,
    ICMP_REPLY_TTL      => ICMP_REPLY_TTL,
    ICMP_ID_INIT        => 0,
    ICMP_ID_INCR        => 2)
    port map(
    in_data         => ig_inbuf.data,
    in_last         => ig_inbuf.last,
    in_valid        => ig_inbuf.valid,
    in_ready        => ig_inbuf.ready,
    in_drop         => drop_ig_gate,
    out_data        => ig_gate.data,
    out_last        => ig_gate.last,
    out_valid       => ig_gate.valid,
    out_ready       => ig_gate.ready,
    icmp_data       => aux_ig_gate.data,
    icmp_last       => aux_ig_gate.last,
    icmp_valid      => aux_ig_gate.valid,
    icmp_ready      => aux_ig_gate.ready,
    router_ipaddr   => router_ip_addr,
    router_submask  => router_sub_mask,
    ipv4_dmac       => ipv4_dmac_ingress,
    noip_dmac       => noip_dmac_ingress,
    time_msec       => router_time_msec,
    clk             => clk_main,
    reset_p         => reset_p);

-- Egress ARP-Proxy (optional).
-- (Listens to egress stream and modifies ingress stream.)
eg_nocrc_write <= eg_nocrc.valid and eg_nocrc.ready;

ig_prox_en : if PROXY_EN_EGRESS generate
    u_ig_proxy : entity work.router_arp_wrapper
        generic map(
        ROUTER_MACADDR  => ROUTER_MACADDR,
        PROXY_SUB_INNER => SUBNET_IS_LCL_PORT,
        RETRY_KBYTES    => PROXY_RETRY_KBYTES,
        RETRY_DLY_CLKS  => PROXY_RETRY_DELAY,
        NOIP_BLOCK_ALL  => NOIP_BLOCK_ALL,
        ICMP_ECHO_BYTES => ICMP_ECHO_BYTES,
        ICMP_REPLY_TTL  => ICMP_REPLY_TTL,
        ICMP_ID_INIT    => 1,
        ICMP_ID_INCR    => 2,
        ARP_CACHE_SIZE  => PROXY_CACHE_SIZE)
        port map(
        lcl_rx_data     => eg_nocrc.data,
        lcl_rx_last     => eg_nocrc.last,
        lcl_rx_write    => eg_nocrc_write,
        lcl_tx_data     => ig_proxy.data,
        lcl_tx_last     => ig_proxy.last,
        lcl_tx_valid    => ig_proxy.valid,
        lcl_tx_ready    => ig_proxy.ready,
        net_rx_data     => ig_gate.data,
        net_rx_last     => ig_gate.last,
        net_rx_valid    => ig_gate.valid,
        net_rx_ready    => ig_gate.ready,
        net_rx_error    => error_ig_proxy,
        net_tx_data     => aux_ig_proxy.data,
        net_tx_last     => aux_ig_proxy.last,
        net_tx_valid    => aux_ig_proxy.valid,
        net_tx_ready    => aux_ig_proxy.ready,
        proxy_ip_addr   => router_ip_addr,
        proxy_sub_addr  => router_sub_addr,
        proxy_sub_mask  => router_sub_mask,
        pkt_dropped     => drop_ig_repl,
        clk             => clk_main,
        reset_p         => reset_p);
end generate;

ig_prox_no : if not PROXY_EN_EGRESS generate
    ig_proxy.data       <= ig_gate.data;
    ig_proxy.last       <= ig_gate.last;
    ig_proxy.valid      <= ig_gate.valid;
    ig_gate.ready       <= ig_proxy.ready;
    aux_ig_proxy.data   <= (others => '0');
    aux_ig_proxy.last   <= '0';
    aux_ig_proxy.valid  <= '0';
    error_ig_proxy      <= '0';
    drop_ig_repl        <= '0';
end generate;

-- Combine all outputs and recalculate CRC.
u_ig_out : entity work.packet_inject
    generic map(
    INPUT_COUNT     => 3,
    MIN_OUT_BYTES   => LCL_FRAME_BYTES_MIN,
    APPEND_FCS      => true)
    port map(
    in0_data        => ig_proxy.data,
    in1_data        => aux_eg_gate.data,
    in2_data        => aux_eg_proxy.data,
    in_last(0)      => ig_proxy.last,
    in_last(1)      => aux_eg_gate.last,
    in_last(2)      => aux_eg_proxy.last,
    in_valid(0)     => ig_proxy.valid,
    in_valid(1)     => aux_eg_gate.valid,
    in_valid(2)     => aux_eg_proxy.valid,
    in_ready(0)     => ig_proxy.ready,
    in_ready(1)     => aux_eg_gate.ready,
    in_ready(2)     => aux_eg_proxy.ready,
    in_error        => error_ig_out,
    out_data        => ig_out.data,
    out_last        => ig_out.last,
    out_valid       => ig_out.valid,
    out_ready       => ig_out.ready,
    clk             => clk_main,
    reset_p         => reset_p);

-----------------------------------------------------------
-- Egress datapath
-----------------------------------------------------------

-- Remove CRC from egress packets.
-- (Data coming straight from switch_core, no need to double-check.)
u_eg_nocrc : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME       => 0,
    APPEND_FCS      => false,
    STRIP_FCS       => true)
    port map(
    in_data         => eg_inraw.data,
    in_last         => eg_inraw.last,
    in_valid        => eg_inraw.valid,
    in_ready        => eg_inraw.ready,
    out_data        => eg_nocrc.data,
    out_last        => eg_nocrc.last,
    out_valid       => eg_nocrc.valid,
    out_ready       => eg_nocrc.ready,
    clk             => clk_main,
    reset_p         => reset_p);

-- Egress IP gateway
u_eg_gate : entity work.router_ip_gateway
    generic map(
    ROUTER_MACADDR      => ROUTER_MACADDR,
    ICMP_ECHO_BYTES     => ICMP_ECHO_BYTES,
    ICMP_REPLY_TTL      => ICMP_REPLY_TTL,
    IPV4_BLOCK_MCAST    => IPV4_BLOCK_MCAST,
    IPV4_BLOCK_FRAGMENT => IPV4_BLOCK_FRAGMENT,
    IPV4_DMAC_FILTER    => IPV4_DMAC_FILTER,
    IPV4_DMAC_REPLACE   => IPV4_DMAC_REPLACE,
    IPV4_SMAC_REPLACE   => IPV4_SMAC_REPLACE,
    NOIP_BLOCK_ALL      => NOIP_BLOCK_ALL,
    NOIP_BLOCK_ARP      => NOIP_BLOCK_ARP,
    NOIP_BLOCK_BCAST    => NOIP_BLOCK_BCAST,
    NOIP_DMAC_REPLACE   => NOIP_DMAC_REPLACE,
    NOIP_SMAC_REPLACE   => NOIP_SMAC_REPLACE,
    ICMP_ID_INIT        => 0,
    ICMP_ID_INCR        => 2)
    port map(
    in_data         => eg_nocrc.data,
    in_last         => eg_nocrc.last,
    in_valid        => eg_nocrc.valid,
    in_ready        => eg_nocrc.ready,
    in_drop         => drop_eg_gate,
    out_data        => eg_gate.data,
    out_last        => eg_gate.last,
    out_valid       => eg_gate.valid,
    out_ready       => eg_gate.ready,
    icmp_data       => aux_eg_gate.data,
    icmp_last       => aux_eg_gate.last,
    icmp_valid      => aux_eg_gate.valid,
    icmp_ready      => aux_eg_gate.ready,
    router_ipaddr   => router_ip_addr,
    router_submask  => router_sub_mask,
    router_link_ok  => link_ok,
    ipv4_dmac       => ipv4_dmac_egress,
    noip_dmac       => noip_dmac_egress,
    time_msec       => router_time_msec,
    clk             => clk_main,
    reset_p         => reset_p);

-- Ingress ARP-Proxy (optional).
-- (Listens to ingress stream and modifies egress stream.)
ig_inbuf_write <= ig_inbuf.valid and ig_inbuf.ready;

eg_prox_en : if PROXY_EN_INGRESS generate
    u_eg_proxy : entity work.router_arp_wrapper
        generic map(
        ROUTER_MACADDR  => ROUTER_MACADDR,
        PROXY_SUB_INNER => not SUBNET_IS_LCL_PORT,
        RETRY_KBYTES    => PROXY_RETRY_KBYTES,
        RETRY_DLY_CLKS  => PROXY_RETRY_DELAY,
        NOIP_BLOCK_ALL  => NOIP_BLOCK_ALL,
        ICMP_ECHO_BYTES => ICMP_ECHO_BYTES,
        ICMP_REPLY_TTL  => ICMP_REPLY_TTL,
        ICMP_ID_INIT    => 1,
        ICMP_ID_INCR    => 2,
        ARP_CACHE_SIZE  => PROXY_CACHE_SIZE)
        port map(
        lcl_rx_data     => ig_inbuf.data,
        lcl_rx_last     => ig_inbuf.last,
        lcl_rx_write    => ig_inbuf_write,
        lcl_tx_data     => eg_proxy.data,
        lcl_tx_last     => eg_proxy.last,
        lcl_tx_valid    => eg_proxy.valid,
        lcl_tx_ready    => eg_proxy.ready,
        net_rx_data     => eg_gate.data,
        net_rx_last     => eg_gate.last,
        net_rx_valid    => eg_gate.valid,
        net_rx_ready    => eg_gate.ready,
        net_rx_error    => error_eg_proxy,
        net_tx_data     => aux_eg_proxy.data,
        net_tx_last     => aux_eg_proxy.last,
        net_tx_valid    => aux_eg_proxy.valid,
        net_tx_ready    => aux_eg_proxy.ready,
        proxy_ip_addr   => router_ip_addr,
        proxy_sub_addr  => router_sub_addr,
        proxy_sub_mask  => router_sub_mask,
        pkt_dropped     => drop_eg_repl,
        clk             => clk_main,
        reset_p         => reset_p);
end generate;

eg_prox_no : if not PROXY_EN_INGRESS generate
    eg_proxy.data       <= eg_gate.data;
    eg_proxy.last       <= eg_gate.last;
    eg_proxy.valid      <= eg_gate.valid;
    eg_gate.ready       <= eg_proxy.ready;
    aux_eg_proxy.data   <= (others => '0');
    aux_eg_proxy.last   <= '0';
    aux_eg_proxy.valid  <= '0';
    error_eg_proxy      <= '0';
    drop_eg_repl        <= '0';
end generate;

-- Combine all outputs and recalculate CRC.
u_eg_out : entity work.packet_inject
    generic map(
    INPUT_COUNT     => 3,
    MIN_OUT_BYTES   => NET_FRAME_BYTES_MIN,
    APPEND_FCS      => true)
    port map(
    in0_data        => eg_proxy.data,
    in1_data        => aux_ig_gate.data,
    in2_data        => aux_ig_proxy.data,
    in_last(0)      => eg_proxy.last,
    in_last(1)      => aux_ig_gate.last,
    in_last(2)      => aux_ig_proxy.last,
    in_valid(0)     => eg_proxy.valid,
    in_valid(1)     => aux_ig_gate.valid,
    in_valid(2)     => aux_ig_proxy.valid,
    in_ready(0)     => eg_proxy.ready,
    in_ready(1)     => aux_ig_gate.ready,
    in_ready(2)     => aux_ig_proxy.ready,
    in_error        => error_eg_out,
    out_data        => eg_out.data,
    out_last        => eg_out.last,
    out_valid       => eg_out.valid,
    out_ready       => eg_out.ready,
    clk             => clk_main,
    reset_p         => reset_p);

end router_inline_top;
