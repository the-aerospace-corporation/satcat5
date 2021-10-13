# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation
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
# This script packages a Vivado IP core: satcat5.port_axi_mailmap
#

# Create a basic IP-core project.
set ip_name "port_mailmap"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus MailMap (Virtual PHY)"
set ip_desc "Virtual Ethernet port suitable for microcontroller polling via ConfigBus with a memory-mapped interface."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     cfgbus_common.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     eth_frame_adjust.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     fifo_smol_sync.vhd
ipcore_add_file $src_dir/common     port_mailmap.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_mem  $src_dir/xilinx     $part_family
ipcore_add_sync $src_dir/xilinx     $part_family
ipcore_add_top  $ip_root            wrap_port_mailmap

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg slave
ipcore_add_ethport Eth sw master

# Set parameters
ipcore_add_param DEV_ADDR devaddr 0
ipcore_add_param MIN_FRAME long 64
ipcore_add_param APPEND_FCS bool true
ipcore_add_param STRIP_FCS bool true

# Package the IP-core.
ipcore_finished
