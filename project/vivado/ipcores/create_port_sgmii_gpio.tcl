# ------------------------------------------------------------------------
# Copyright 2020, 2021, 2022 The Aerospace Corporation
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
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_file $src_dir/xilinx/port_sgmii_gpio.vhd
ipcore_add_file $src_dir/xilinx/sgmii_*.vhd
ipcore_add_top  $ip_root/wrap_port_sgmii_gpio.vhd

# Connect everything except the SGMII port.
ipcore_add_ethport Eth sw master
ipcore_add_refopt PtpRef tref
ipcore_add_clock clk_125    {}  slave 125000000
ipcore_add_clock clk_200    Eth slave 200000000
ipcore_add_clock clk_625_00 {}  slave 625000000
ipcore_add_clock clk_625_90 {}  slave 625000000
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
ipcore_add_param TX_INVERT bool false \
    {Invert outgoing signal?}
ipcore_add_param TX_IOSTD string "LVDS_25" \
    {I/O standard for outgoing signal}
ipcore_add_param RX_INVERT bool false \
    {Invert incoming signal?}
ipcore_add_param RX_IOSTD string "LVDS_25" \
    {I/O standard for incoming signal}
ipcore_add_param RX_BIAS_EN bool false \
    {Enable built-in DC biasing?}
ipcore_add_param RX_TERM_EN bool true \
    {Enable built-in differential termination?}
ipcore_add_param SHAKE_WAIT bool true \
    {Wait for handshake completion before transmitting data?}

# Package the IP-core.
ipcore_finished
