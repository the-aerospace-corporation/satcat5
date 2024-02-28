# ------------------------------------------------------------------------
# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.port_sgmii_raw
#

# Lookup product family for the current project.
variable iproot [file normalize [file dirname [info script]]]
source $iproot/../part_family.tcl

# Use provided MGT type, or set default based on part family.
if [info exists sgmii_raw_mgt_type] {
    puts "Using MGT-Type: ${sgmii_raw_mgt_type}"
} elseif {$part_family == "7series"} {
    set sgmii_raw_mgt_type {gtx}
} elseif {$part_family == "ultrascale" || $part_family == "ultraplus"} {
    set sgmii_raw_mgt_type {gty}
} else {
    error "Unsupported part family: ${part_family}"
}
set core_name "sgmii_raw_${sgmii_raw_mgt_type}"

# Default MGT reference clock frequency 125MHz, can be overridden.
# Note: Extra zeros ".000" are required by the Xilinx MGT IP-core.
if ![info exists sgmii_raw_refclk_mhz] {
    variable sgmii_raw_refclk_mhz {125.000}
}
variable sgmii_raw_refclk_hz [expr {round($sgmii_raw_refclk_mhz * 1000000)}]

# Create a basic IP-core project.
set ip_name "port_sgmii_raw_${sgmii_raw_mgt_type}"
set ip_vers "1.0"
set ip_disp "SatCat5 SGMII PHY (MGT-Raw)"
set ip_desc "SatCat5 SGMII port using MGT in raw mode."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Attempt to create the underlying MGT IP-core.
# This step will fail on parts that don't have an MGT.
source $ip_root/../generate_sgmii_gtx.tcl
set errcode [catch {
    generate_sgmii_raw ${core_name}0 $sgmii_raw_mgt_type $sgmii_raw_refclk_mhz REFCLK0_Q0
    generate_sgmii_raw ${core_name}1 $sgmii_raw_mgt_type $sgmii_raw_refclk_mhz REFCLK0_Q1
    ipcore_add_xci ${core_name}0
    ipcore_add_xci ${core_name}1
} errstring]

if {$errcode != 0} {
    puts "Cannot create MGT core: $errstring"
    ipcore_abort
    return
}

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_file $src_dir/xilinx/port_sgmii_raw.vhd
ipcore_add_top  $ip_root/wrap_port_sgmii_raw.vhd

# Connect all interface ports.
ipcore_add_ethport Eth sw master
ipcore_add_refopt PtpRef tref
ipcore_add_clock gtsysclk Eth slave
ipcore_add_clock out_clk_125 out_reset_p master 125000000
ipcore_add_reset out_reset_p ACTIVE_HIGH master
ipcore_add_reset reset_p ACTIVE_HIGH slave
ipcore_add_sgmii SGMII sgmii master
ipcore_add_diffclock GTREFCLK gtrefclk slave $sgmii_raw_refclk_hz
ipcore_add_gpio shared_out
ipcore_add_gpio shared_in

# Set parameters
ipcore_add_param SHAKE_WAIT bool false\
    {Block data transfer until MAC/PHY handshake completed?}
ipcore_add_param SHARED_EN bool true\
    {Include shared logic? Required for first MGT in each quad.}
ipcore_add_param REFCLK_SRC long 0\
    {Select the MGT reference source (0 or 1).}
ipcore_add_param MGT_TYPE string $sgmii_raw_mgt_type\
    {Transceiver type} false
ipcore_add_param REFCLK_FREQ_HZ string $sgmii_raw_refclk_hz\
    {Frequency of MGT reference clock} false

# Enable the shared_* ports based on SHARED_EN.
set_property enablement_dependency {$SHARED_EN} [ipx::get_bus_interfaces GTREFCLK -of_objects $ip]
set_property enablement_dependency {$SHARED_EN} [ipx::get_ports out_clk_125 -of_objects $ip]
set_property enablement_dependency {$SHARED_EN} [ipx::get_ports out_reset_p -of_objects $ip]
set_property enablement_dependency {$SHARED_EN} [ipx::get_ports shared_out -of_objects $ip]
set_property enablement_dependency {!$SHARED_EN} [ipx::get_ports shared_in -of_objects $ip]

# Package the IP-core.
ipcore_finished
