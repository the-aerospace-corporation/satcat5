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
# This script packages a Vivado IP core: satcat5.port_sgmii_gpio
#

# Create a basic IP-core project.
set ip_name "port_sgmii_gpio"
set ip_vers "1.0"
set ip_disp "SatCat5 SGMII PHY (GPIO)"
set ip_desc "SatCat5 SGMII port using oversampled GPIO."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     eth_dec8b10b.vhd
ipcore_add_file $src_dir/common     eth_enc8b10b.vhd
ipcore_add_file $src_dir/common     eth_enc8b10b_table.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     eth_preambles.vhd
ipcore_add_file $src_dir/common     port_sgmii_common.vhd
ipcore_add_file $src_dir/common     smol_fifo.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_file $src_dir/xilinx     port_sgmii_gpio.vhd
ipcore_add_file $src_dir/xilinx     sgmii_data_slip.vhd
ipcore_add_file $src_dir/xilinx     sgmii_data_sync.vhd
ipcore_add_file $src_dir/xilinx     sgmii_input_fifo.vhd
ipcore_add_file $src_dir/xilinx     sgmii_serdes_rx.vhd
ipcore_add_file $src_dir/xilinx     sgmii_serdes_tx.vhd
ipcore_add_file $src_dir/xilinx     synchronization.vhd
ipcore_add_top  $ip_root            wrap_port_sgmii_gpio

# Connect everything except the SGMII port.
ipcore_add_ethport Eth sw master
ipcore_add_clock clk_125 {}
ipcore_add_clock clk_200 Eth
ipcore_add_clock clk_625_00 {}
ipcore_add_clock clk_625_90 {}
ipcore_add_reset reset_p ACTIVE_HIGH

# Connect the SGMII port.
set intf [ipx::add_bus_interface SGMII $ip]
set_property abstraction_type_vlnv xilinx.com:interface:sgmii_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:sgmii:1.0 $intf
set_property interface_mode master $intf

set_property physical_name sgmii_rxp    [ipx::add_port_map RXP  $intf]
set_property physical_name sgmii_rxn    [ipx::add_port_map RXN  $intf]
set_property physical_name sgmii_txp    [ipx::add_port_map TXP  $intf]
set_property physical_name sgmii_txn    [ipx::add_port_map TXN  $intf]

# Set parameters
ipcore_add_param TX_INVERT bool false
ipcore_add_param RX_INVERT bool false
ipcore_add_param RX_BIAS_EN bool false
ipcore_add_param RX_TERM_EN bool true

# Package the IP-core.
ipcore_finished
