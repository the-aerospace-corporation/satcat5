# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.port_gmii_internal
#

# Create a basic IP-core project.
set ip_name "port_stream"
set ip_vers "1.0"
set ip_disp "SatCat5 AXI-Stream Port"
set ip_desc "SatCat5 adapter for AXI-Stream ports."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_stream.vhd

# Connect the AXI-Stream port (Rx).
set intf [ipx::add_bus_interface Rx $ip]
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 $intf
set_property interface_mode slave $intf

set_property physical_name rx_data      [ipx::add_port_map TDATA    $intf]
set_property physical_name rx_error     [ipx::add_port_map TUSER    $intf]
set_property physical_name rx_last      [ipx::add_port_map TLAST    $intf]
set_property physical_name rx_valid     [ipx::add_port_map TVALID   $intf]
set_property physical_name rx_ready     [ipx::add_port_map TREADY   $intf]

# Connect the AXI-Stream port (Tx).
set intf [ipx::add_bus_interface Tx $ip]
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 $intf
set_property interface_mode master $intf

set_property physical_name tx_data      [ipx::add_port_map TDATA    $intf]
set_property physical_name tx_last      [ipx::add_port_map TLAST    $intf]
set_property physical_name tx_valid     [ipx::add_port_map TVALID   $intf]
set_property physical_name tx_ready     [ipx::add_port_map TREADY   $intf]

# Connect all remaining ports.
ipcore_add_ethport Eth sw master
ipcore_add_refopt PtpRef tref
ipcore_add_clock rx_clk Rx
ipcore_add_reset rx_reset ACTIVE_HIGH
ipcore_add_clock tx_clk Tx
ipcore_add_reset tx_reset ACTIVE_HIGH

# Add the estimated-rate parameter.
set rxclk [ipcore_add_param RX_CLK_HZ long 100000000 \
    {Frequency of "rx_clk" (Hz), required for PTP timestamps only.}]
set txclk [ipcore_add_param TX_CLK_HZ long 100000000 \
    {Frequency of "tx_clk" (Hz), required for PTP timestamps only.}]
set dreg [ipcore_add_param DELAY_REG bool true \
    {Add delay register for improved timing? (Recommended)}]
set rate [ipcore_add_param RATE_MBPS long 1000 \
    {Nominal network communication rate (Mbps)}]
set rx_min_frm [ipcore_add_param RX_MIN_FRM long 64 \
    {Pad Rx data from user to minimum length? (bytes)}]
set rx_has_fcs [ipcore_add_param RX_HAS_FCS bool false \
    {Does Rx data from user include FCS?}]
set tx_has_fcs [ipcore_add_param TX_HAS_FCS bool false \
    {Should Tx data to user include FCS?}]
set_property value_validation_type range_long $rate
set_property value_validation_range_minimum 1 $rate
set_property value_validation_range_maximum 2000 $rate
set_property enablement_tcl_expr {$PTP_ENABLE} $rxclk
set_property enablement_tcl_expr {$PTP_ENABLE} $txclk

# Package the IP-core.
ipcore_finished
