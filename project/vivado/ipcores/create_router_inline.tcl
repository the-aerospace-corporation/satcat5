# ------------------------------------------------------------------------
# Copyright 2020, 2021 The Aerospace Corporation
#
# This file is part of SatCat5.
#
# SatCat5 is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# SatCat5 is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.router_inline
#

# Create a basic IP-core project.
set ip_name "router_inline"
set ip_vers "1.0"
set ip_disp "SatCat5 Inline IPv4 Router"
set ip_desc "An IPv4 router placed between a switch and a designated uplink port."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     cfgbus_common.vhd
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     eth_frame_adjust.vhd
ipcore_add_file $src_dir/common     eth_frame_check.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     fifo_large_sync.vhd
ipcore_add_file $src_dir/common     fifo_packet.vhd
ipcore_add_file $src_dir/common     fifo_smol_async.vhd
ipcore_add_file $src_dir/common     fifo_smol_resize.vhd
ipcore_add_file $src_dir/common     fifo_smol_sync.vhd
ipcore_add_file $src_dir/common     packet_inject.vhd
ipcore_add_file $src_dir/common     router_arp_cache.vhd
ipcore_add_file $src_dir/common     router_arp_parse.vhd
ipcore_add_file $src_dir/common     router_arp_proxy.vhd
ipcore_add_file $src_dir/common     router_arp_request.vhd
ipcore_add_file $src_dir/common     router_arp_update.vhd
ipcore_add_file $src_dir/common     router_arp_wrapper.vhd
ipcore_add_file $src_dir/common     router_config_axi.vhd
ipcore_add_file $src_dir/common     router_config_static.vhd
ipcore_add_file $src_dir/common     router_common.vhd
ipcore_add_file $src_dir/common     router_icmp_send.vhd
ipcore_add_file $src_dir/common     router_inline_top.vhd
ipcore_add_file $src_dir/common     router_ip_gateway.vhd
ipcore_add_file $src_dir/common     router_mac_replace.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_mem  $src_dir/xilinx     $part_family
ipcore_add_sync $src_dir/xilinx     $part_family
ipcore_add_top  $ip_root            wrap_router_inline

# Connect I/O ports
ipcore_add_ethport LocalPort lcl master
ipcore_add_ethport NetPort net slave
ipcore_add_axilite CtrlAxi axi_clk axi_aresetn axi
ipcore_add_reset reset_p ACTIVE_HIGH

# Set parameters
ipcore_add_param STATIC_CONFIG          bool false
ipcore_add_param STATIC_IPADDR          hexstring {C0A80101}
ipcore_add_param STATIC_SUBADDR         hexstring {C0A80100}
ipcore_add_param STATIC_SUBMASK         hexstring {FFFFFF00}
ipcore_add_param STATIC_NOIP_DMAC_EG    hexstring {FFFFFFFFFFFF}
ipcore_add_param STATIC_NOIP_DMAC_IG    hexstring {FFFFFFFFFFFF}
ipcore_add_param AXI_ADDR_WIDTH         long 32
ipcore_add_param ROUTER_MACADDR         hexstring {5A5ADEADBEEF}
ipcore_add_param ROUTER_REFCLK_HZ       long 125000000
ipcore_add_param SUBNET_IS_LCL_PORT     bool false
ipcore_add_param PROXY_EN_EGRESS        bool true
ipcore_add_param PROXY_EN_INGRESS       bool true
ipcore_add_param PROXY_RETRY_KBYTES     long 4
ipcore_add_param PROXY_CACHE_SIZE       long 32
ipcore_add_param IPV4_BLOCK_MCAST       bool true
ipcore_add_param IPV4_BLOCK_FRAGMENT    bool true
ipcore_add_param IPV4_DMAC_FILTER       bool true
ipcore_add_param IPV4_DMAC_REPLACE      bool true
ipcore_add_param IPV4_SMAC_REPLACE      bool true
ipcore_add_param NOIP_BLOCK_ALL         bool true
ipcore_add_param NOIP_BLOCK_ARP         bool true
ipcore_add_param NOIP_BLOCK_BCAST       bool true
ipcore_add_param NOIP_DMAC_REPLACE      bool true
ipcore_add_param NOIP_SMAC_REPLACE      bool true
ipcore_add_param LCL_FRAME_BYTES_MIN    long 64
ipcore_add_param NET_FRAME_BYTES_MIN    long 64

# Enable ports and parameters depending on configuration.
set_property enablement_dependency {!$STATIC_CONFIG} [ipx::get_bus_interfaces CtrlAxi -of_objects $ip]
set_property enablement_dependency {!$STATIC_CONFIG} [ipx::get_bus_interfaces axi_clk -of_objects $ip]
set_property enablement_dependency {!$STATIC_CONFIG} [ipx::get_bus_interfaces axi_aresetn -of_objects $ip]
set_property enablement_dependency {$STATIC_CONFIG} [ipx::get_bus_interfaces reset_p -of_objects $ip]
set_property enablement_tcl_expr {!$STATIC_CONFIG} [ipx::get_user_parameters AXI_ADDR_WIDTH -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG} [ipx::get_user_parameters STATIC_IPADDR -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG} [ipx::get_user_parameters STATIC_SUBADDR -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG} [ipx::get_user_parameters STATIC_SUBMASK -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG && $NOIP_DMAC_REPLACE && !$NOIP_BLOCK_ALL} [ipx::get_user_parameters STATIC_NOIP_DMAC_EG -of_objects $ip]
set_property enablement_tcl_expr {$STATIC_CONFIG && $NOIP_DMAC_REPLACE && !$NOIP_BLOCK_ALL} [ipx::get_user_parameters STATIC_NOIP_DMAC_IG -of_objects $ip]

# Package the IP-core.
ipcore_finished
