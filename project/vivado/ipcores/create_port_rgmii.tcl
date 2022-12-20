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
# This script packages a Vivado IP core: satcat5.port_rgmii
#

# Create a basic IP-core project.
set ip_name "port_rgmii"
set ip_vers "1.0"
set ip_disp "SatCat5 RGMII PHY"
set ip_desc "SatCat5 adapter for RGMII ports."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_rgmii.vhd

# Connect everything except the RGMII port.
ipcore_add_ethport Eth sw master
ipcore_add_refopt PtpRef tref
ipcore_add_clock clk_125 Eth slave 125000000
ipcore_add_clock clk_txc {}
ipcore_add_reset reset_p ACTIVE_HIGH

# Connect the RGMII port.
set intf [ipx::add_bus_interface RGMII $ip]
set_property abstraction_type_vlnv xilinx.com:interface:rgmii_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:rgmii:1.0 $intf
set_property interface_mode master $intf

set_property physical_name rgmii_txc    [ipx::add_port_map TXC      $intf]
set_property physical_name rgmii_txd    [ipx::add_port_map TD       $intf]
set_property physical_name rgmii_txctl  [ipx::add_port_map TX_CTL   $intf]
set_property physical_name rgmii_rxc    [ipx::add_port_map RXC      $intf]
set_property physical_name rgmii_rxd    [ipx::add_port_map RD       $intf]
set_property physical_name rgmii_rxctl  [ipx::add_port_map RX_CTL   $intf]

# Associate clock with the RGMII port.
set_property value clk_125 [ipx::add_bus_parameter ASSOCIATED_BUSIF $intf]

# Set parameters
ipcore_add_param RXCLK_ALIGN bool false \
    {Instantiate an MMCM for precise clock-phase alignment?}
ipcore_add_param RXCLK_LOCAL bool false \
    {Instantiate a local clock buffer for Rx clock?}
ipcore_add_param RXCLK_GLOBL bool true \
    {Instantiate a global clock buffer for Rx clock? (Recommended)}
ipcore_add_param RXCLK_DELAY long 0 \
    {Added delay for Rx-clock signal, in picoseconds}
ipcore_add_param RXDAT_DELAY long 2000 \
    {Added delay for Rx-data signal, in picoseconds}

# Package the IP-core.
ipcore_finished
