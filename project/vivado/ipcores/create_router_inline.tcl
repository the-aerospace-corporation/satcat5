# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.router_inline
#

# Create a basic IP-core project.
set ip_name "router_inline"
set ip_vers "1.0"
set ip_disp "SatCat5 Inline IPv4 Router"
set ip_desc "An IPv4 router placed between a switch and a designated uplink port."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_router_inline.vhd

# Connect I/O ports
ipcore_add_ethport LocalPort lcl master
ipcore_add_ethport NetPort net slave
ipcore_add_axilite CtrlAxi axi_clk axi_aresetn axi
ipcore_add_reset reset_p ACTIVE_HIGH

# Set parameters
ipcore_add_param STATIC_CONFIG          bool false \
    {Configuration set at build-time?}
ipcore_add_param STATIC_IPADDR          hexstring {C0A80101} \
    {Router IP-address (hex)}
ipcore_add_param STATIC_SUBADDR         hexstring {C0A80100} \
    {Subnet base address (hex)}
ipcore_add_param STATIC_SUBMASK         hexstring {FFFFFF00} \
    {Subnet mask (hex)}
ipcore_add_param STATIC_IPV4_DMAC_EG    hexstring {DEADBEEFCAFE} \
    {Forwarding address for IPv4 frames on NetPort (Do not use broadcast)}
ipcore_add_param STATIC_IPV4_DMAC_IG    hexstring {DEADBEEFCAFE} \
    {Forwarding address for IPv4 frames on LocalPort (Do not use broadcast)}
ipcore_add_param STATIC_NOIP_DMAC_EG    hexstring {FFFFFFFFFFFF} \
    {Forwarding address for non-IP frames on NetPort}
ipcore_add_param STATIC_NOIP_DMAC_IG    hexstring {FFFFFFFFFFFF} \
    {Forwarding address for non-IP frames on LocalPort}
ipcore_add_param AXI_ADDR_WIDTH         long 32 \
    {Bits in AXI address word}
ipcore_add_param ROUTER_MACADDR         hexstring {5A5ADEADBEEF} \
    {Router MAC address (hex)}
ipcore_add_param ROUTER_REFCLK_HZ       long 125000000 \
    {Frequency of NetPort transmit clock (Hz)}
ipcore_add_param SUBNET_IS_LCL_PORT     bool false \
    {Is the narrow subnet on LocalPort (true) or NetPort (false)?}
ipcore_add_param PROXY_EN_EGRESS        bool true \
    {Enable Proxy-ARP on LocalPort? (i.e., Emulating responses for devices on NetPort.)}
ipcore_add_param PROXY_EN_INGRESS       bool true \
    {Enable Proxy-ARP on NetPort? (i.e., Emulating responses for devices on LocalPort.)}
ipcore_add_param PROXY_RETRY_KBYTES     long 4 \
    {Buffer size for IP frames with uncached MAC address}
ipcore_add_param PROXY_CACHE_SIZE       long 32 \
    {Size of ARP cache}
ipcore_add_param IPV4_BLOCK_MCAST       bool true \
    {Block multicast IPv4 packets?}
ipcore_add_param IPV4_BLOCK_FRAGMENT    bool true \
    {Block fragmented IPv4 packets?}
ipcore_add_param IPV4_DMAC_FILTER       bool true \
    {Block IPv4 packets sent to a MAC address that is not the router?}
ipcore_add_param IPV4_DMAC_REPLACE      bool true \
    {Replace destination MAC of IPv4 packets?}
ipcore_add_param IPV4_SMAC_REPLACE      bool true \
    {Replace source MAC of IPv4 packets? (Recommended)}
ipcore_add_param NOIP_BLOCK_ALL         bool true \
    {Block all non-IPv4 frames?}
ipcore_add_param NOIP_BLOCK_ARP         bool true \
    {Block Address Resolution Protocol (ARP) frames?}
ipcore_add_param NOIP_BLOCK_BCAST       bool true \
    {Block non-IPv4 frames with a broadcast destination address?}
ipcore_add_param NOIP_DMAC_REPLACE      bool true \
    {Replace destination MAC of non-IPv4 frames?}
ipcore_add_param NOIP_SMAC_REPLACE      bool true \
    {Replace source MAC of non-IPv4 frames? (Recommended)}
ipcore_add_param LCL_FRAME_BYTES_MIN    long 64 \
    {Minimum length of Ethernet frames on LocalPort (total bytes including FCS)}
ipcore_add_param NET_FRAME_BYTES_MIN    long 64 \
    {Minimum length of Ethernet frames on NetPort (total bytes including FCS)}

# Enable ports and parameters depending on configuration.
set_property enablement_dependency {!$STATIC_CONFIG} [ipx::get_bus_interfaces CtrlAxi -of_objects $ip]
set_property enablement_dependency {!$STATIC_CONFIG} [ipx::get_bus_interfaces axi_clk -of_objects $ip]
set_property enablement_dependency {!$STATIC_CONFIG} [ipx::get_bus_interfaces axi_aresetn -of_objects $ip]
set_property enablement_dependency {$STATIC_CONFIG} [ipx::get_bus_interfaces reset_p -of_objects $ip]
set_property enablement_tcl_expr {!$STATIC_CONFIG} [ipx::get_user_parameters AXI_ADDR_WIDTH -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG} [ipx::get_user_parameters STATIC_IPADDR -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG} [ipx::get_user_parameters STATIC_SUBADDR -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG} [ipx::get_user_parameters STATIC_SUBMASK -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG && $IPV4_DMAC_REPLACE && !$PROXY_EN_INGRESS} [ipx::get_user_parameters STATIC_NOIP_DMAC_EG -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG && $IPV4_DMAC_REPLACE && !$PROXY_EN_EGRESS} [ipx::get_user_parameters STATIC_NOIP_DMAC_IG -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG && $NOIP_DMAC_REPLACE && !$NOIP_BLOCK_ALL} [ipx::get_user_parameters STATIC_NOIP_DMAC_EG -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG && $NOIP_DMAC_REPLACE && !$NOIP_BLOCK_ALL} [ipx::get_user_parameters STATIC_NOIP_DMAC_IG -of_objects $ip]

# Package the IP-core.
ipcore_finished
