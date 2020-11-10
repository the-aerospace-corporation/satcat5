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
# This script packages a Vivado IP core: satcat5.port_sgmii_gtx
#

# Default GTX location X0Y0, but can be overridden.
# Unclear if there's any way to do this using GUI Customization Parameters.
# May be possible using pre-synthesis hooks or LOC constraints in the parent project? See also:
# https://forums.xilinx.com/t5/Vivado-TCL-Community/How-to-include-pre-post-TCL-scripts-to-custom-IP/m-p/649102#M3927
if ![info exists gtx_loc] {
    set gtx_loc X0Y0
}

# Create a basic IP-core project.
set ip_name "port_sgmii_gtx_$gtx_loc"
set ip_vers "1.0"
set ip_disp "SatCat5 SGMII PHY (GTX=$gtx_loc)"
set ip_desc "SatCat5 SGMII port using GTX-SERDES."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Create the underlying GTX-to-SGMII IP-core.
source $ip_root/../generate_sgmii_gtx.tcl
generate_sgmii_gtx $gtx_loc sgmii_gtx0
ipcore_add_xci sgmii_gtx0

# Add the resulting XCI file to the project.
set core_xci [get_files *.xci]
ipcore_add_file [file dirname $core_xci] [file tail $core_xci]

# Add all required source files:
#               Path                Filename
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     eth_preambles.vhd
ipcore_add_file $src_dir/common     smol_fifo.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_file $src_dir/xilinx     port_sgmii_gtx.vhd
ipcore_add_file $src_dir/xilinx     synchronization.vhd
ipcore_add_top  $ip_root            wrap_port_sgmii_gtx

# Connect everything except the GTX ports.
ipcore_add_ethport Eth sw master
ipcore_add_clock clkin_200 Eth
ipcore_add_reset reset_p ACTIVE_HIGH

# Connect the GTX reference clock.
set intf [ipx::add_bus_interface GTREF125 $ip]
set_property abstraction_type_vlnv xilinx.com:interface:diff_clock_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:diff_clock:1.0 $intf
set_property interface_mode slave $intf

set_property physical_name gtref_125p   [ipx::add_port_map CLK_P $intf]
set_property physical_name gtref_125n   [ipx::add_port_map CLK_N $intf]

# Connect the GTX I/O (SGMII) port.
set intf [ipx::add_bus_interface SGMII $ip]
set_property abstraction_type_vlnv xilinx.com:interface:sgmii_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:sgmii:1.0 $intf
set_property interface_mode master $intf

set_property physical_name sgmii_rxp    [ipx::add_port_map RXP  $intf]
set_property physical_name sgmii_rxn    [ipx::add_port_map RXN  $intf]
set_property physical_name sgmii_txp    [ipx::add_port_map TXP  $intf]
set_property physical_name sgmii_txn    [ipx::add_port_map TXN  $intf]

# Package the IP-core.
ipcore_finished
