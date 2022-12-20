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
# This script packages a Vivado IP core: satcat5.port_gmii_internal
#

# Create a basic IP-core project.
set ip_name "port_gmii_internal"
set ip_vers "1.0"
set ip_disp "SatCat5 Internal GMII PHY"
set ip_desc "SatCat5 adapter for internal GMII ports, like those the Zynq 70xx-PS."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_gmii_internal.vhd

# Connect everything except the GMII port.
ipcore_add_ethport Eth sw master
ipcore_add_refopt PtpRef tref
ipcore_add_clock clk_125 Eth slave 125000000
ipcore_add_reset reset_p ACTIVE_HIGH

# Connect the GMII port.
set intf [ipx::add_bus_interface GMII $ip]
set_property abstraction_type_vlnv xilinx.com:interface:gmii_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:gmii:1.0 $intf
set_property interface_mode slave $intf

set_property physical_name gmii_rxd     [ipx::add_port_map TXD      $intf]
set_property physical_name gmii_rxerr   [ipx::add_port_map TX_ER    $intf]
set_property physical_name gmii_col     [ipx::add_port_map COL      $intf]
set_property physical_name gmii_crs     [ipx::add_port_map CRS      $intf]
set_property physical_name gmii_txen    [ipx::add_port_map RX_DV    $intf]
set_property physical_name gmii_rxc     [ipx::add_port_map RX_CLK   $intf]
set_property physical_name gmii_txerr   [ipx::add_port_map RX_ER    $intf]
set_property physical_name gmii_txc     [ipx::add_port_map TX_CLK   $intf]
set_property physical_name gmii_rxdv    [ipx::add_port_map TX_EN    $intf]
set_property physical_name gmii_txd     [ipx::add_port_map RXD      $intf]

# Associate clock with the GMII port.
set_property value clk_125 [ipx::add_bus_parameter ASSOCIATED_BUSIF $intf]

# Package the IP-core.
ipcore_finished
