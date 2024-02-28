# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.port_serial_auto
#

# Create a basic IP-core project.
set ip_name "port_serial_auto"
set ip_vers "1.0"
set ip_disp "SatCat5 4-Wire SPI/UART PHY"
set ip_desc "Mixed-media Ethernet-over-SPI / Ethernet-over-UART auto-detecting port."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_serial_auto.vhd

# Connect I/O ports
ipcore_add_gpio ext_pads
ipcore_add_ethport Eth sw master
ipcore_add_clock refclk Eth
ipcore_add_reset reset_p ACTIVE_HIGH
ipcore_add_cfgopt Cfg cfg

# Set parameters
ipcore_add_param CLKREF_HZ long 100000000 \
    {Frequency of "refclk" signal (Hz)}
ipcore_add_param SPI_MODE long 3 \
    {Default polarity and phase of SPI clock (Mode = 0-3)}
ipcore_add_param UART_BAUD long 921600 \
    {Default baud rate for UART mode}
ipcore_add_param PULLUP_EN bool true \
    {Enable pullups on all input signals? (Recommended)}
ipcore_add_param FORCE_SHDN bool false \
    {Drive all signals low when port is held in reset/shutdown?}

# Package the IP-core.
ipcore_finished
