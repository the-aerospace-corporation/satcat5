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
# This script packages a Vivado IP core: satcat5.port_crosslink
#

# Create a basic IP-core project.
set ip_name "port_crosslink"
set ip_vers "1.0"
set ip_disp "SatCat5 Switch-to-Switch Crosslink"
set ip_desc "Crosslink for connecting two SatCat5 switch cores back-to-back."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     eth_frame_adjust.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     port_crosslink.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_sync $src_dir/xilinx     $part_family
ipcore_add_top  $ip_root            wrap_port_crosslink

# Connect I/O ports
ipcore_add_ethport PortA pa master
ipcore_add_ethport PortB pb master
ipcore_add_clock ref_clk {PortA PortB}
ipcore_add_reset reset_p ACTIVE_HIGH

# Set parameters
ipcore_add_param RUNT_PORTA bool false
ipcore_add_param RUNT_PORTB bool false
ipcore_add_param RATE_DIV long 2

# Package the IP-core.
ipcore_finished
