# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.gmii_to_spi
#
# Create IP: Satcat5 GMII to SPI Core

set ip_name "switch_gmii_to_spi"
set ip_vers "1.0"
set ip_disp "SatCat5 GMII to SPI"
set ip_desc "A two-port switch, configured to translate a GMII internal interface (typically found on Zynq 70xx-PS) to EoS/SPI."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $src_dir/common/switch_gmii_to_spi.vhd

# Connect the clock and reset ports
ipcore_add_clock clk_125 "" slave 125000000
ipcore_add_reset reset_p ACTIVE_HIGH

# Connect the GMII port
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

# Package the IP-core.
ipcore_finished
