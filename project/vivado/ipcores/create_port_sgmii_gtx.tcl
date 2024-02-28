# ------------------------------------------------------------------------
# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.port_sgmii_gtx
#

# Default GTX location X0Y0, but can be overridden.
# Unclear if there's any way to do this using GUI Customization Parameters.
# May be possible using pre-synthesis hooks or LOC constraints in the parent project? See also:
# https://forums.xilinx.com/t5/Vivado-TCL-Community/How-to-include-pre-post-TCL-scripts-to-custom-IP/m-p/649102#M3927
if ![info exists sgmii_gtx_loc] {
    variable sgmii_gtx_loc X0Y0
}

# Default GTX reference clock frequency 125MHz, can be overridden
# Note: Extra zeros ".000" are forbidden by the Xilinx SGMII IP-core.
if ![info exists sgmii_gtx_refclk_mhz] {
    variable sgmii_gtx_refclk_mhz 125
}
variable sgmii_gtx_refclk_hz [expr {round($sgmii_gtx_refclk_mhz * 1000000)}]

# Create a basic IP-core project.
set ip_name "port_sgmii_gtx_${sgmii_gtx_loc}"
set ip_vers "1.0"
set ip_disp "SatCat5 SGMII PHY (MGT)"
set ip_desc "SatCat5 SGMII port using GTX-SERDES."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Create the underlying GTX-to-SGMII IP-core(s),
# and set various platform-specific parameters.
source $ip_root/../generate_sgmii_gtx.tcl
if {$part_family == "7series"} {
    # 7 series parts need IDELAYCTRL clock = 200MHz
    set bufg_freq_hz 200000000
    set shared_qpll 1
    generate_sgmii_gtx $sgmii_gtx_loc sgmii_gtx2 1 $sgmii_gtx_refclk_mhz
    generate_sgmii_gtx $sgmii_gtx_loc sgmii_gtx3 0 $sgmii_gtx_refclk_mhz
    ipcore_add_xci sgmii_gtx2
    ipcore_add_xci sgmii_gtx3
} elseif {$part_family == "ultrascale" || $part_family == "ultraplus"} {
    # Ultrascale/Ultrascale+ parts need DRP clock = 50MHz
    set bufg_freq_hz 50000000
    set shared_qpll 0
    generate_sgmii_gtx $sgmii_gtx_loc sgmii_gtx0 1 $sgmii_gtx_refclk_mhz
    generate_sgmii_gtx $sgmii_gtx_loc sgmii_gtx1 0 $sgmii_gtx_refclk_mhz
    ipcore_add_xci sgmii_gtx0
    ipcore_add_xci sgmii_gtx1
} else {
    error "Unsupported part family: ${part_family}"
}


# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_file $src_dir/xilinx/port_sgmii_gtx.vhd
ipcore_add_top  $ip_root/wrap_port_sgmii_gtx.vhd

# Connect all interface ports.
ipcore_add_ethport Eth sw master
ipcore_add_refopt PtpRef tref
ipcore_add_clock clkin_bufg Eth slave $bufg_freq_hz
ipcore_add_reset reset_p ACTIVE_HIGH
ipcore_add_diffclock GTREFCLK gtrefclk slave $sgmii_gtx_refclk_hz
ipcore_add_sgmii SGMII sgmii master
ipcore_add_gpio shared_out
ipcore_add_gpio shared_in

# Set parameters
ipcore_add_param AUTONEG_EN bool true\
    {Enable Auto-Negotiation? Typically enabled with the exception of SFP to RJ45 modules.}
ipcore_add_param SHARED_EN bool true\
    {Include shared logic? Required for first MGT in each quad.}
ipcore_add_param GTX_LOCATION string $sgmii_gtx_loc\
    {Transceiver identifier} false
ipcore_add_param SHARED_QPLL string $shared_qpll\
    {Does this MGT use a shared QPLL resource?} false
ipcore_add_param REFCLK_FREQ_HZ string $sgmii_gtx_refclk_hz\
    {Frequency of GTX reference clock} false
ipcore_add_param CLKIN_FREQ_HZ string $bufg_freq_hz\
    {Frequency of logic clock} false

# Enable the shared_* ports based on SHARED_EN.
set_property enablement_dependency {$SHARED_EN} [ipx::get_bus_interfaces GTREFCLK -of_objects $ip]
set_property enablement_dependency {$SHARED_EN} [ipx::get_ports shared_out -of_objects $ip]
set_property enablement_dependency {!$SHARED_EN} [ipx::get_ports shared_in -of_objects $ip]

# Package the IP-core.
ipcore_finished
