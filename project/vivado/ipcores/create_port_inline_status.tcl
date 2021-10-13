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
# This script packages a Vivado IP core: satcat5.port_status_inline
#

# Create a basic IP-core project.
set ip_name "port_inline_status"
set ip_vers "1.0"
set ip_disp "SatCat5 Inline Status/Keep-Alive"
set ip_desc "Inline port adapter that injects status or keep-alive messages."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     config_send_status.vhd
ipcore_add_file $src_dir/common     eth_frame_adjust.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     fifo_large_sync.vhd
ipcore_add_file $src_dir/common     fifo_smol_sync.vhd
ipcore_add_file $src_dir/common     packet_inject.vhd
ipcore_add_file $src_dir/common     port_inline_status.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_sync $src_dir/xilinx     $part_family
ipcore_add_top  $ip_root            wrap_port_inline_status

# Connect I/O ports
ipcore_add_ethport LocalPort lcl master
ipcore_add_ethport NetPort net slave
ipcore_add_gpio status_val
ipcore_add_gpio status_wr_t

# Set parameters
ipcore_add_param SEND_EGRESS        bool true
ipcore_add_param SEND_INGRESS       bool true
ipcore_add_param MSG_BYTES          long 0
ipcore_add_param MSG_ETYPE          hexstring {5C00}
ipcore_add_param MAC_DEST           hexstring {FFFFFFFFFFFF}
ipcore_add_param MAC_SOURCE         hexstring {5A5ADEADBEEF}
ipcore_add_param AUTO_DELAY_CLKS    long 125000000
ipcore_add_param MIN_FRAME_BYTES    long 64

# Enable ports and parameters depending on configuration.
set_property enablement_dependency {$MSG_BYTES > 0} [ipx::get_ports status_val -of_objects $ip]
set_property enablement_dependency {$AUTO_DELAY_CLKS = 0} [ipx::get_ports status_wr_t -of_objects $ip]

# Package the IP-core.
ipcore_finished
