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
# This script packages a Vivado IP core: satcat5.switch_dual
#

# Create a basic IP-core project.
set ip_name "switch_dual"
set ip_vers "1.0"
set ip_disp "SatCat5 Dual-port Ethernet Switch"
set ip_desc "A two-port switch, typically used for interface-type adapation."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     eth_frame_check.vhd
ipcore_add_file $src_dir/common     fifo_packet.vhd
ipcore_add_file $src_dir/common     fifo_smol_async.vhd
ipcore_add_file $src_dir/common     fifo_smol_resize.vhd
ipcore_add_file $src_dir/common     fifo_smol_sync.vhd
ipcore_add_file $src_dir/common     port_passthrough.vhd
ipcore_add_file $src_dir/common     switch_dual.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_mem  $src_dir/xilinx     $part_family
ipcore_add_sync $src_dir/xilinx     $part_family
ipcore_add_top  $ip_root            wrap_switch_dual

# Connect I/O ports
ipcore_add_ethport "PortA" "pa" "slave"
ipcore_add_ethport "PortB" "pb" "slave"
ipcore_add_gpio errvec_t

# Set parameters
ipcore_add_param ALLOW_JUMBO bool false
ipcore_add_param ALLOW_RUNT bool false
ipcore_add_param OBUF_KBYTES long 2

# Package the IP-core.
ipcore_finished
