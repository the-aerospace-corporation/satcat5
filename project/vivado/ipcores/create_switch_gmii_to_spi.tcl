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
# This script packages a Vivado IP core: satcat5.gmii_to_spi
#
# Create IP: Satcat5 GMII to SPI Core

set ip_name "switch_gmii_to_spi"
set ip_vers "1.0"
set ip_disp "SatCat5 GMII to SPI"
set ip_desc "A two-port switch, configured to translate a GMII internal interface (typically found on Zynq 70xx-PS) to EoS/SPI."

set ip_root [file normalize [file dirname [info script]]]

source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     cfgbus_common.vhd
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     eth_frame_adjust.vhd
ipcore_add_file $src_dir/common     eth_frame_check.vhd
ipcore_add_file $src_dir/common     eth_preamble_rx.vhd
ipcore_add_file $src_dir/common     eth_preamble_tx.vhd
ipcore_add_file $src_dir/common     fifo_packet.vhd
ipcore_add_file $src_dir/common     fifo_smol_async.vhd
ipcore_add_file $src_dir/common     fifo_smol_resize.vhd
ipcore_add_file $src_dir/common     fifo_smol_sync.vhd
ipcore_add_file $src_dir/common     io_spi_controller.vhd
ipcore_add_file $src_dir/common     port_adapter.vhd
ipcore_add_file $src_dir/common     port_gmii_internal.vhd
ipcore_add_file $src_dir/common     port_passthrough.vhd
ipcore_add_file $src_dir/common     port_serial_spi_controller.vhd
ipcore_add_file $src_dir/common     slip_decoder.vhd
ipcore_add_file $src_dir/common     slip_encoder.vhd
ipcore_add_file $src_dir/common     switch_dual.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_io   $src_dir/xilinx     $part_family
ipcore_add_mem  $src_dir/xilinx     $part_family
ipcore_add_sync $src_dir/xilinx     $part_family
ipcore_add_top  $src_dir/common     switch_gmii_to_spi

# Connect the clock and reset ports
ipcore_add_clock clk_125 ""
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
