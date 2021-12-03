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
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     cfgbus_common.vhd
ipcore_add_file $src_dir/common     cfgbus_port_stats.vhd
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     eth_frame_adjust.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     eth_frame_check.vhd
ipcore_add_file $src_dir/common     eth_frame_parcrc.vhd
ipcore_add_file $src_dir/common     eth_frame_vstrip.vhd
ipcore_add_file $src_dir/common     eth_frame_vtag.vhd
ipcore_add_file $src_dir/common     eth_pause_ctrl.vhd
ipcore_add_file $src_dir/common     eth_statistics.vhd
ipcore_add_file $src_dir/common     fifo_packet.vhd
ipcore_add_file $src_dir/common     fifo_priority.vhd
ipcore_add_file $src_dir/common     fifo_repack.vhd
ipcore_add_file $src_dir/common     fifo_smol_async.vhd
ipcore_add_file $src_dir/common     fifo_smol_bytes.vhd
ipcore_add_file $src_dir/common     fifo_smol_resize.vhd
ipcore_add_file $src_dir/common     fifo_smol_sync.vhd
ipcore_add_file $src_dir/common     mac_core.vhd
ipcore_add_file $src_dir/common     mac_counter.vhd
ipcore_add_file $src_dir/common     mac_igmp_simple.vhd
ipcore_add_file $src_dir/common     mac_lookup.vhd
ipcore_add_file $src_dir/common     mac_priority.vhd
ipcore_add_file $src_dir/common     mac_vlan_mask.vhd
ipcore_add_file $src_dir/common     packet_delay.vhd
ipcore_add_file $src_dir/common     packet_inject.vhd
ipcore_add_file $src_dir/common     packet_round_robin.vhd
ipcore_add_file $src_dir/common     port_statistics.vhd
ipcore_add_file $src_dir/common     portx_statistics.vhd
ipcore_add_file $src_dir/common     switch_core.vhd
ipcore_add_file $src_dir/common     switch_port_rx.vhd
ipcore_add_file $src_dir/common     switch_port_tx.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_file $src_dir/common     tcam_cache_nru2.vhd
ipcore_add_file $src_dir/common     tcam_cache_plru.vhd
ipcore_add_file $src_dir/common     tcam_core.vhd
ipcore_add_file $src_dir/common     tcam_maxlen.vhd
ipcore_add_file $src_dir/common     tcam_table.vhd
ipcore_add_mem  $src_dir/xilinx     $part_family
ipcore_add_sync $src_dir/xilinx     $part_family
ipcore_add_top  $ip_root            wrap_switch_core

# Connect all the basic I/O ports
ipcore_add_clock core_clk {}
ipcore_add_reset reset_p ACTIVE_HIGH
ipcore_add_gpio scrub_req_t
ipcore_add_gpio errvec_t
ipcore_add_cfgopt Cfg cfg

# Set parameters
set pcount [ipcore_add_param PORT_COUNT long 3]
set xcount [ipcore_add_param PORTX_COUNT long 0]
set dwidth [ipcore_add_param DATAPATH_BYTES long 3]
ipcore_add_param STATS_ENABLE bool false
ipcore_add_param STATS_DEVADDR devaddr 1
ipcore_add_param CORE_CLK_HZ long 200000000
ipcore_add_param SUPPORT_PAUSE bool true
ipcore_add_param SUPPORT_PTP bool false
ipcore_add_param SUPPORT_VLAN bool false
ipcore_add_param ALLOW_JUMBO bool false
ipcore_add_param ALLOW_RUNT bool false
ipcore_add_param IBUF_KBYTES long 2
ipcore_add_param HBUF_KBYTES long 0
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
set_property value_validation_range_minimum 0 $pcount
set_property value_validation_range_maximum $PORT_COUNT_MAX $pcount

set PORTX_COUNT_MAX 8
set_property value_validation_type range_long $xcount
set_property value_validation_range_minimum 0 $xcount
set_property value_validation_range_maximum $PORTX_COUNT_MAX $xcount

# Enable ports and parameters depending on configuration.
set_property enablement_dependency {$CFG_ENABLE || $STATS_ENABLE} [ipx::get_bus_interfaces Cfg -of_objects $ip]
set_property enablement_tcl_expr {$STATS_ENABLE} [ipx::get_user_parameters STATS_DEVADDR -of_objects $ip]

# Add each of the Ethernet ports with logic to show/hide.
# (HDL always has PORT_COUNT_MAX, enable first N depending on GUI setting.)
for {set idx 0} {$idx < $PORT_COUNT_MAX} {incr idx} {
    set name [format "Port%02d" $idx]
    set port [format "p%02d" $idx]
    set intf [ipcore_add_ethport $name $port slave]
    set_property enablement_dependency "$idx < \$PORT_COUNT" $intf
}

for {set idx 0} {$idx < $PORTX_COUNT_MAX} {incr idx} {
    set name [format "PortX%02d" $idx]
    set port [format "x%02d" $idx]
    set intf [ipcore_add_xgeport $name $port slave]
    set_property enablement_dependency "$idx < \$PORTX_COUNT" $intf
}

# Package the IP-core.
ipcore_finished
