# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.port_rmii
#

# Create a basic IP-core project.
set ip_name "port_rmii"
set ip_vers "1.0"
set ip_disp "SatCat5 RMII PHY"
set ip_desc "SatCat5 adapter for RMII ports."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_rmii.vhd

# Connect everything except the RMII port.
ipcore_add_ethport Eth sw master
ipcore_add_refopt PtpRef tref
ipcore_add_clock ctrl_clkin {}
ipcore_add_clock rmii_clkin {Eth rmii_clkout} slave 50000000
ipcore_add_gpio  rmii_clkout
ipcore_add_reset reset_p ACTIVE_HIGH

# Connect the RMII port.
set intf [ipx::add_bus_interface RMII $ip]
set_property abstraction_type_vlnv xilinx.com:interface:rmii_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:rmii:1.0 $intf
set_property interface_mode master $intf

set_property physical_name rmii_rxd     [ipx::add_port_map RXD      $intf]
set_property physical_name rmii_rxen    [ipx::add_port_map CRS_DV   $intf]
set_property physical_name rmii_rxer    [ipx::add_port_map RX_ER    $intf]
set_property physical_name rmii_txd     [ipx::add_port_map TXD      $intf]
set_property physical_name rmii_txen    [ipx::add_port_map TX_EN    $intf]

# Associate clock with the RMII port.
set_property value rmii_clkin [ipx::add_bus_parameter ASSOCIATED_BUSIF $intf]

# Set parameters
ipcore_add_param MODE_CLKOUT bool true \
    {Is RMII clock signal an output from this block?}

# Enable ports and parameters depending on configuration.
set_property enablement_dependency {$MODE_CLKOUT} [ipx::get_ports rmii_clkout -of_objects $ip]

# Package the IP-core.
ipcore_finished
