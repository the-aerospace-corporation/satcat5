# ------------------------------------------------------------------------
# Copyright 2020 The Aerospace Corporation
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
# This script packages a Vivado IP core: satcat5.switch_core
#

# Create a basic IP-core project.
set ip_name "switch_core"
set ip_vers "1.0"
set ip_disp "SatCat5 N-Port Ethernet Switch"
set ip_desc "SatCat5 general-purpose Layer-2 Ethernet Switch."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     config_stats_axi.vhd
ipcore_add_file $src_dir/common     config_stats_uart.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     eth_frame_check.vhd
ipcore_add_file $src_dir/common     eth_pause_ctrl.vhd
ipcore_add_file $src_dir/common     fifo_packet.vhd
ipcore_add_file $src_dir/common     fifo_smol.vhd
ipcore_add_file $src_dir/common     mac_lookup_binary.vhd
ipcore_add_file $src_dir/common     mac_lookup_brute.vhd
ipcore_add_file $src_dir/common     mac_lookup_generic.vhd
ipcore_add_file $src_dir/common     mac_lookup_lutram.vhd
ipcore_add_file $src_dir/common     mac_lookup_parshift.vhd
ipcore_add_file $src_dir/common     mac_lookup_simple.vhd
ipcore_add_file $src_dir/common     mac_lookup_stream.vhd
ipcore_add_file $src_dir/common     packet_delay.vhd
ipcore_add_file $src_dir/common     packet_round_robin.vhd
ipcore_add_file $src_dir/common     port_statistics.vhd
ipcore_add_file $src_dir/common     switch_core.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_file $src_dir/xilinx     lutram_7series.vhd
ipcore_add_file $src_dir/xilinx     synchronization.vhd
ipcore_add_top  $ip_root            wrap_switch_core

# Connect all the basic I/O ports
ipcore_add_clock core_clk {}
ipcore_add_reset reset_p ACTIVE_HIGH
ipcore_add_gpio scrub_req_t
ipcore_add_gpio errvec_t
ipcore_add_axilite CtrlAxi axi_clk axi_aresetn axi
ipcore_add_gpio uart_txd
ipcore_add_gpio uart_rxd

# Set parameters
set pcount [ipcore_add_param PORT_COUNT long 3]
set dwidth [ipcore_add_param DATAPATH_BYTES long 3]
ipcore_add_param STATS_AXI_EN bool false
ipcore_add_param AXI_ADDR_WIDTH long 32
ipcore_add_param STATS_UART_EN bool false
ipcore_add_param STATS_UART_BAUD long 921600
ipcore_add_param CORE_CLK_HZ long 200000000
ipcore_add_param SUPPORT_PAUSE bool true
ipcore_add_param ALLOW_JUMBO bool false
ipcore_add_param ALLOW_RUNT bool false
ipcore_add_param IBUF_KBYTES long 2
ipcore_add_param OBUF_KBYTES long 6
ipcore_add_param MAC_TABLE_SIZE long 64
ipcore_add_param SCRUB_TIMEOUT long 15

# Set min/max range on the DATAPATH_BYTES parameter.
set_property value_validation_type range_long $dwidth
set_property value_validation_range_minimum 1 $dwidth
set_property value_validation_range_maximum 6 $dwidth

# Set min/max range on the PORT_COUNT parameter.
set PORT_COUNT_MAX 32
set_property value_validation_type range_long $pcount
set_property value_validation_range_minimum 3 $pcount
set_property value_validation_range_maximum $PORT_COUNT_MAX $pcount

# Set tie-off values for optional input ports.
set_property driver_value 1 [ipx::get_ports uart_rxd -of_objects $ip]

# Enable ports and parameters depending on configuration.
set_property enablement_dependency {$STATS_AXI_EN} [ipx::get_bus_interfaces CtrlAxi -of_objects $ip]
set_property enablement_dependency {$STATS_AXI_EN} [ipx::get_bus_interfaces axi_clk -of_objects $ip]
set_property enablement_dependency {$STATS_AXI_EN} [ipx::get_bus_interfaces axi_aresetn -of_objects $ip]
set_property enablement_dependency {$STATS_UART_EN} [ipx::get_ports uart_txd -of_objects $ip]
set_property enablement_dependency {$STATS_UART_EN} [ipx::get_ports uart_rxd -of_objects $ip]
set_property enablement_tcl_expr {$STATS_AXI_EN} [ipx::get_user_parameters AXI_ADDR_WIDTH -of_objects $ip]
set_property enablement_tcl_expr {$STATS_UART_EN} [ipx::get_user_parameters STATS_UART_BAUD -of_objects $ip]

# Add each of the Ethernet ports with logic to show/hide.
# (HDL always has PORT_COUNT_MAX, enable first N depending on GUI setting.)
for {set idx 0} {$idx < $PORT_COUNT_MAX} {incr idx} {
    set name [format "Port%02d" $idx]
    set port [format "p%02d" $idx]
    set intf [ipcore_add_ethport $name $port slave]
    set_property enablement_dependency "$idx < \$PORT_COUNT" $intf
}

# Package the IP-core.
ipcore_finished
