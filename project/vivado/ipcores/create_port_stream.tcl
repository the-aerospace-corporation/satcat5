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
# This script packages a Vivado IP core: satcat5.port_gmii_internal
#

# Create a basic IP-core project.
set ip_name "port_stream"
set ip_vers "1.0"
set ip_disp "SatCat5 AXI-Stream Port"
set ip_desc "SatCat5 adapter for AXI-Stream ports."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_top  $ip_root            wrap_port_stream

# Connect the AXI-Stream port (Rx).
set intf [ipx::add_bus_interface Rx $ip]
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 $intf
set_property interface_mode slave $intf

set_property physical_name rx_data      [ipx::add_port_map TDATA    $intf]
set_property physical_name rx_last      [ipx::add_port_map TLAST    $intf]
set_property physical_name rx_valid     [ipx::add_port_map TVALID   $intf]
set_property physical_name rx_ready     [ipx::add_port_map TREADY   $intf]

# Connect the AXI-Stream port (Tx).
set intf [ipx::add_bus_interface Tx $ip]
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 $intf
set_property interface_mode master $intf

set_property physical_name tx_data      [ipx::add_port_map TDATA    $intf]
set_property physical_name tx_last      [ipx::add_port_map TLAST    $intf]
set_property physical_name tx_valid     [ipx::add_port_map TVALID   $intf]
set_property physical_name tx_ready     [ipx::add_port_map TREADY   $intf]

# Connect all remaining ports.
ipcore_add_ethport Eth sw master
ipcore_add_clock rx_clk Rx
ipcore_add_reset rx_reset ACTIVE_HIGH
ipcore_add_clock tx_clk Tx
ipcore_add_reset tx_reset ACTIVE_HIGH

# Add the estimated-rate parameter.
set rate [ipcore_add_param RATE_MBPS long 1000]
set_property value_validation_type range_long $rate
set_property value_validation_range_minimum 1 $rate
set_property value_validation_range_maximum 2000 $rate

# Package the IP-core.
ipcore_finished
