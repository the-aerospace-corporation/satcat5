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
# This script packages a Vivado IP core: satcat5.port_serial_i2c_peripheral
#

# Create a basic IP-core project.
set ip_name "port_serial_i2c_peripheral"
set ip_vers "1.0"
set ip_disp "SatCat5 I2C PHY (Peripheral)"
set ip_desc "Mixed-media Ethernet-over-I2C port, acting as bus peripheral."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     cfgbus_common.vhd
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     io_i2c_controller.vhd
ipcore_add_file $src_dir/common     io_i2c_peripheral.vhd
ipcore_add_file $src_dir/common     port_serial_i2c_peripheral.vhd
ipcore_add_file $src_dir/common     slip_decoder.vhd
ipcore_add_file $src_dir/common     slip_encoder.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_io   $src_dir/xilinx     $part_family
ipcore_add_sync $src_dir/xilinx     $part_family
ipcore_add_top  $ip_root            wrap_port_serial_i2c_peripheral

# Connect I/O ports
ipcore_add_gpio i2c_sclk
ipcore_add_gpio i2c_sdata
ipcore_add_gpio rts_out
ipcore_add_ethport Eth sw master
ipcore_add_clock ref_clk Eth
ipcore_add_reset reset_p ACTIVE_HIGH
ipcore_add_cfgopt Cfg cfg

# Set parameters
ipcore_add_param I2C_ADDR bitstring 1010101
ipcore_add_param CLKREF_HZ long 100000000

# Package the IP-core.
ipcore_finished
