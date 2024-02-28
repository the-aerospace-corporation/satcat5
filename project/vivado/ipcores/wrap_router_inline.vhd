--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "router_inline_top" and "router_axi_config"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.switch_types.all;

entity wrap_router_inline is
    generic (
    -- Router parameters (see router_inline_top)
    STATIC_CONFIG       : boolean := false; -- Fixed configuration or use AXI?
    STATIC_IPADDR       : std_logic_vector(31 downto 0);    -- Static IP address
    STATIC_SUBADDR      : std_logic_vector(31 downto 0);    -- Static subnet addr
    STATIC_SUBMASK      : std_logic_vector(31 downto 0);    -- Static subnet mask
    STATIC_IPV4_DMAC_EG : std_logic_vector(47 downto 0);    -- Destination address (IPv4)
    STATIC_IPV4_DMAC_IG : std_logic_vector(47 downto 0);    -- Destination address (IPv4)
    STATIC_NOIP_DMAC_EG : std_logic_vector(47 downto 0);    -- Destination address (Non-IP)
    STATIC_NOIP_DMAC_IG : std_logic_vector(47 downto 0);    -- Destination address (Non-IP)
    ROUTER_MACADDR      : std_logic_vector(47 downto 0);    -- MAC address for this router
    ROUTER_REFCLK_HZ    : natural := 125_000_000; -- Operating clock frequency (net_tx_clk)
    SUBNET_IS_LCL_PORT  : boolean := false; -- Which port has the local subnet?
    PROXY_EN_EGRESS     : boolean := true;  -- Enable Proxy-ARP on egress? (LCL to NET)
    PROXY_EN_INGRESS    : boolean := true;  -- Enable Proxy-ARP on ingress? (NET to LCL)
    PROXY_RETRY_KBYTES  : natural := 4;     -- Buffer size for ARP-miss
    PROXY_CACHE_SIZE    : integer := 32;    -- Ingress ARP cache size
    IPV4_BLOCK_MCAST    : boolean := true;  -- Block IPv4 multicast?
    IPV4_BLOCK_FRAGMENT : boolean := true;  -- Block fragmented frames?
    IPV4_DMAC_FILTER    : boolean := true;  -- Destination MAC must be router?
    IPV4_DMAC_REPLACE   : boolean := true;  -- Replace destination MAC in output?
    IPV4_SMAC_REPLACE   : boolean := true;  -- Replace source MAC in output?
    NOIP_BLOCK_ALL      : boolean := true;  -- Block all non-IP?
    NOIP_BLOCK_ARP      : boolean := true;  -- Block all ARP frames?
    NOIP_BLOCK_BCAST    : boolean := true;  -- Block non-IP broadcast?
    NOIP_DMAC_REPLACE   : boolean := true;  -- Replace destination MAC in output?
    NOIP_SMAC_REPLACE   : boolean := true;  -- Replace source MAC in output?
    LCL_FRAME_BYTES_MIN : integer := 64;
    NET_FRAME_BYTES_MIN : integer := 64;
    AXI_ADDR_WIDTH      : natural := 32);   -- AXI-Lite address width
    port (
    -- Local switch port.
    lcl_rx_clk      : out std_logic;
    lcl_rx_data     : out std_logic_vector(7 downto 0);
    lcl_rx_last     : out std_logic;
    lcl_rx_write    : out std_logic;
    lcl_rx_error    : out std_logic;
    lcl_rx_rate     : out std_logic_vector(15 downto 0);
    lcl_rx_status   : out std_logic_vector(7 downto 0);
    lcl_rx_tsof     : out std_logic_vector(47 downto 0);
    lcl_rx_reset    : out std_logic;
    lcl_tx_clk      : out std_logic;
    lcl_tx_data     : in  std_logic_vector(7 downto 0);
    lcl_tx_last     : in  std_logic;
    lcl_tx_valid    : in  std_logic;
    lcl_tx_ready    : out std_logic;
    lcl_tx_error    : out std_logic;
    lcl_tx_pstart   : out std_logic;
    lcl_tx_tnow     : out std_logic_vector(47 downto 0);
    lcl_tx_reset    : out std_logic;

    -- Remote network port.
    net_rx_clk      : in  std_logic;
    net_rx_data     : in  std_logic_vector(7 downto 0);
    net_rx_last     : in  std_logic;
    net_rx_write    : in  std_logic;
    net_rx_error    : in  std_logic;
    net_rx_rate     : in  std_logic_vector(15 downto 0);
    net_rx_status   : in  std_logic_vector(7 downto 0);
    net_rx_tsof     : in  std_logic_vector(47 downto 0);
    net_rx_reset    : in  std_logic;
    net_tx_clk      : in  std_logic;
    net_tx_data     : out std_logic_vector(7 downto 0);
    net_tx_last     : out std_logic;
    net_tx_valid    : out std_logic;
    net_tx_ready    : in  std_logic;
    net_tx_error    : in  std_logic;
    net_tx_pstart   : in  std_logic;
    net_tx_tnow     : in  std_logic_vector(47 downto 0);
    net_tx_reset    : in  std_logic;

    -- External reset (static mode only)
    reset_p         : in  std_logic;

    -- AXI-Lite interface (dynamic mode only)
    axi_clk         : in  std_logic;
    axi_aresetn     : in  std_logic;
    axi_awaddr      : in  std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
    axi_awvalid     : in  std_logic;
    axi_awready     : out std_logic;
    axi_wdata       : in  std_logic_vector(31 downto 0);
    axi_wstrb       : in  std_logic_vector(3 downto 0) := "1111";
    axi_wvalid      : in  std_logic;
    axi_wready      : out std_logic;
    axi_bresp       : out std_logic_vector(1 downto 0);
    axi_bvalid      : out std_logic;
    axi_bready      : in  std_logic;
    axi_araddr      : in  std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
    axi_arvalid     : in  std_logic;
    axi_arready     : out std_logic;
    axi_rdata       : out std_logic_vector(31 downto 0);
    axi_rresp       : out std_logic_vector(1 downto 0);
    axi_rvalid      : out std_logic;
    axi_rready      : in  std_logic);
end wrap_router_inline;

architecture wrap_router_inline of wrap_router_inline is

signal lcl_rxd, net_rxd : port_rx_m2s;
signal lcl_txd, net_txd : port_tx_s2m;
signal lcl_txc, net_txc : port_tx_m2s;

signal cfg_ip_addr      : ip_addr_t;
signal cfg_sub_addr     : ip_addr_t;
signal cfg_sub_mask     : ip_addr_t;
signal cfg_reset_p      : std_logic;
signal ipv4_dmac_eg     : mac_addr_t;
signal ipv4_dmac_ig     : mac_addr_t;
signal noip_dmac_eg     : mac_addr_t;
signal noip_dmac_ig     : mac_addr_t;
signal rtr_clk          : std_logic;
signal rtr_drop_count   : bcount_t;
signal rtr_time_msec    : timestamp_t;

begin

-- Convert port signals.
lcl_rx_clk      <= lcl_rxd.clk;
lcl_rx_data     <= lcl_rxd.data;
lcl_rx_last     <= lcl_rxd.last;
lcl_rx_write    <= lcl_rxd.write;
lcl_rx_error    <= lcl_rxd.rxerr;
lcl_rx_rate     <= lcl_rxd.rate;
lcl_rx_status   <= lcl_rxd.status;
lcl_rx_tsof     <= std_logic_vector(lcl_rxd.tsof);
lcl_rx_reset    <= lcl_rxd.reset_p;
lcl_tx_clk      <= lcl_txc.clk;
lcl_tx_ready    <= lcl_txc.ready;
lcl_tx_pstart   <= lcl_txc.pstart;
lcl_tx_tnow     <= std_logic_vector(lcl_txc.tnow);
lcl_tx_error    <= lcl_txc.txerr;
lcl_tx_reset    <= lcl_txc.reset_p;
lcl_txd.data    <= lcl_tx_data;
lcl_txd.last    <= lcl_tx_last;
lcl_txd.valid   <= lcl_tx_valid;

net_rxd.clk     <= net_rx_clk;
net_rxd.data    <= net_rx_data;
net_rxd.last    <= net_rx_last;
net_rxd.write   <= net_rx_write;
net_rxd.rxerr   <= net_rx_error;
net_rxd.rate    <= net_rx_rate;
net_rxd.status  <= net_rx_status;
net_rxd.tsof    <= unsigned(net_rx_tsof);
net_rxd.reset_p <= net_rx_reset;
net_txc.clk     <= net_tx_clk;
net_txc.ready   <= net_tx_ready;
net_txc.pstart  <= net_tx_pstart;
net_txc.tnow    <= unsigned(net_tx_tnow);
net_txc.txerr   <= net_tx_error;
net_txc.reset_p <= net_tx_reset;
net_tx_data     <= net_txd.data;
net_tx_last     <= net_txd.last;
net_tx_valid    <= net_txd.valid;

-- Configuration logic.
gen_static : if STATIC_CONFIG generate
    -- Static configuration block.
    u_config : entity work.router_config_static
        generic map(
        CLKREF_HZ       => ROUTER_REFCLK_HZ,
        R_IP_ADDR       => STATIC_IPADDR,
        R_SUB_ADDR      => STATIC_SUBADDR,
        R_SUB_MASK      => STATIC_SUBMASK,
        R_IPV4_DMAC_EG  => STATIC_IPV4_DMAC_EG,
        R_IPV4_DMAC_IG  => STATIC_IPV4_DMAC_IG,
        R_NOIP_DMAC_EG  => STATIC_NOIP_DMAC_EG,
        R_NOIP_DMAC_IG  => STATIC_NOIP_DMAC_IG)
        port map(
        cfg_ip_addr     => cfg_ip_addr,
        cfg_sub_addr    => cfg_sub_addr,
        cfg_sub_mask    => cfg_sub_mask,
        cfg_reset_p     => cfg_reset_p,
        ipv4_dmac_eg    => ipv4_dmac_eg,
        ipv4_dmac_ig    => ipv4_dmac_ig,
        noip_dmac_eg    => noip_dmac_eg,
        noip_dmac_ig    => noip_dmac_ig,
        rtr_clk         => rtr_clk,
        rtr_time_msec   => rtr_time_msec,
        ext_reset_p     => reset_p);

    -- Tie off unused AXI signals.
    axi_awready     <= '0';
    axi_wready      <= '0';
    axi_bresp       <= (others => '0');
    axi_bvalid      <= '0';
    axi_arready     <= '0';
    axi_rdata       <= (others => '0');
    axi_rresp       <= (others => '0');
    axi_rvalid      <= '0';
end generate;

gen_dynamic : if not STATIC_CONFIG generate
    -- Dynamic configuration block.
    u_config : entity work.router_config_axi
        generic map(
        CLKREF_HZ       => ROUTER_REFCLK_HZ,
        IPV4_REG_EN     => IPV4_DMAC_REPLACE and not (PROXY_EN_EGRESS and PROXY_EN_INGRESS),
        NOIP_REG_EN     => NOIP_DMAC_REPLACE and not NOIP_BLOCK_ALL,
        ADDR_WIDTH      => AXI_ADDR_WIDTH)
        port map(
        cfg_ip_addr     => cfg_ip_addr,
        cfg_sub_addr    => cfg_sub_addr,
        cfg_sub_mask    => cfg_sub_mask,
        cfg_reset_p     => cfg_reset_p,
        ipv4_dmac_eg    => ipv4_dmac_eg,
        ipv4_dmac_ig    => ipv4_dmac_ig,
        noip_dmac_eg    => noip_dmac_eg,
        noip_dmac_ig    => noip_dmac_ig,
        rtr_clk         => rtr_clk,
        rtr_drop_count  => rtr_drop_count,
        rtr_time_msec   => rtr_time_msec,
        axi_clk         => axi_clk,
        axi_aresetn     => axi_aresetn,
        axi_awaddr      => axi_awaddr,
        axi_awvalid     => axi_awvalid,
        axi_awready     => axi_awready,
        axi_wdata       => axi_wdata,
        axi_wstrb       => axi_wstrb,
        axi_wvalid      => axi_wvalid,
        axi_wready      => axi_wready,
        axi_bresp       => axi_bresp,
        axi_bvalid      => axi_bvalid,
        axi_bready      => axi_bready,
        axi_araddr      => axi_araddr,
        axi_arvalid     => axi_arvalid,
        axi_arready     => axi_arready,
        axi_rdata       => axi_rdata,
        axi_rresp       => axi_rresp,
        axi_rvalid      => axi_rvalid,
        axi_rready      => axi_rready);
end generate;

-- Router unit.
u_router : entity work.router_inline_top
    generic map(
    ROUTER_MACADDR      => ROUTER_MACADDR,
    SUBNET_IS_LCL_PORT  => SUBNET_IS_LCL_PORT,
    PROXY_EN_EGRESS     => PROXY_EN_EGRESS,
    PROXY_EN_INGRESS    => PROXY_EN_INGRESS,
    PROXY_RETRY_KBYTES  => PROXY_RETRY_KBYTES,
    PROXY_RETRY_DELAY   => ROUTER_REFCLK_HZ / 125,
    PROXY_CACHE_SIZE    => PROXY_CACHE_SIZE,
    IPV4_BLOCK_MCAST    => IPV4_BLOCK_MCAST ,
    IPV4_BLOCK_FRAGMENT => IPV4_BLOCK_FRAGMENT,
    IPV4_DMAC_FILTER    => IPV4_DMAC_FILTER,
    IPV4_DMAC_REPLACE   => IPV4_DMAC_REPLACE,
    IPV4_SMAC_REPLACE   => IPV4_SMAC_REPLACE,
    NOIP_BLOCK_ALL      => NOIP_BLOCK_ALL,
    NOIP_BLOCK_ARP      => NOIP_BLOCK_ARP,
    NOIP_BLOCK_BCAST    => NOIP_BLOCK_BCAST,
    NOIP_DMAC_REPLACE   => NOIP_DMAC_REPLACE,
    NOIP_SMAC_REPLACE   => NOIP_SMAC_REPLACE,
    LCL_FRAME_BYTES_MIN => LCL_FRAME_BYTES_MIN,
    NET_FRAME_BYTES_MIN => NET_FRAME_BYTES_MIN)
    port map(
    lcl_rx_data         => lcl_rxd,
    lcl_tx_data         => lcl_txd,
    lcl_tx_ctrl         => lcl_txc,
    net_rx_data         => net_rxd,
    net_tx_data         => net_txd,
    net_tx_ctrl         => net_txc,
    router_ip_addr      => cfg_ip_addr,
    router_sub_addr     => cfg_sub_addr,
    router_sub_mask     => cfg_sub_mask,
    router_time_msec    => rtr_time_msec,
    ipv4_dmac_egress    => ipv4_dmac_eg,
    ipv4_dmac_ingress   => ipv4_dmac_ig,
    noip_dmac_egress    => noip_dmac_eg,
    noip_dmac_ingress   => noip_dmac_ig,
    router_drop_clk     => rtr_clk,
    router_drop_count   => rtr_drop_count,
    ext_reset_p         => cfg_reset_p);

end wrap_router_inline;
