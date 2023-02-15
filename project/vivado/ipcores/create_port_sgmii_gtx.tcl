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
# This script packages a Vivado IP core: satcat5.port_sgmii_gtx
#

# Default GTX location X0Y0, but can be overridden.
# Unclear if there's any way to do this using GUI Customization Parameters.
# May be possible using pre-synthesis hooks or LOC constraints in the parent project? See also:
# https://forums.xilinx.com/t5/Vivado-TCL-Community/How-to-include-pre-post-TCL-scripts-to-custom-IP/m-p/649102#M3927
if ![info exists gtx_loc] {
    set gtx_loc X0Y0
}

# Default GTX reference clock frequency 125MHz, can be overridden
if ![info exists refclk_freq_mhz] {
    set refclk_freq_mhz 125
}

# Create a basic IP-core project.
set ip_name "port_sgmii_gtx_$gtx_loc"
set ip_vers "1.0"
set ip_disp "SatCat5 SGMII PHY (MGT)"
set ip_desc "SatCat5 SGMII port using GTX-SERDES."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Set expected frequency for "independent_clock_bufg".
if {$part_family == "7series"} {
    # 7 series parts need IDELAYCTRL clock = 200MHz
    set bufg_freq_hz 200000000
} elseif {$part_family == "ultrascale" || $part_family == "ultraplus"} {
    # Ultrascale/Ultrascale+ parts need DRP clock = 50MHz
    set bufg_freq_hz 50000000
} else {
    error "Unsupported part family: ${part_family}"
}

# Create the underlying GTX-to-SGMII IP-core.
source $ip_root/../generate_sgmii_gtx.tcl
generate_sgmii_gtx $gtx_loc sgmii_gtx0 true $refclk_freq_mhz
ipcore_add_xci sgmii_gtx0

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_file $src_dir/xilinx/port_sgmii_gtx.vhd
ipcore_add_top  $ip_root/wrap_port_sgmii_gtx.vhd

# Connect everything except the GTX ports.
ipcore_add_ethport Eth sw master
ipcore_add_refopt PtpRef tref
ipcore_add_clock clkin_bufg Eth slave $bufg_freq_hz
ipcore_add_reset reset_p ACTIVE_HIGH

# Set parameters
set refclk_freq_hz [expr {round($refclk_freq_mhz * 1000000)}]
ipcore_add_param AUTONEG_EN bool true\
    {Enable Auto-Negotiation? Typically enabled with the exception of SFP to RJ45 modules.}
ipcore_add_param GTX_LOCATION string $gtx_loc\
    {Transceiver identifier} false
ipcore_add_param REFCLK_FREQ_HZ string $refclk_freq_hz\
    {Frequency of GTX reference clock} false
ipcore_add_param CLKIN_FREQ_HZ string $bufg_freq_hz\
    {Frequency of logic clock} false

# Connect the GTX reference clock.
set intf [ipx::add_bus_interface GTREFCLK $ip]
set_property abstraction_type_vlnv xilinx.com:interface:diff_clock_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:diff_clock:1.0 $intf
set_property interface_mode slave $intf
set_property physical_name gtrefclk_p   [ipx::add_port_map CLK_P $intf]
set_property physical_name gtrefclk_n   [ipx::add_port_map CLK_N $intf]
set_property value $refclk_freq_hz      [ipx::add_bus_parameter FREQ_HZ $intf]

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
