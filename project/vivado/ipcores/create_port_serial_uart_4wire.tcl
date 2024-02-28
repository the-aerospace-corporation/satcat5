# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.port_serial_uart_4wire
#

# Create a basic IP-core project.
set ip_name "port_serial_uart_4wire"
set ip_vers "1.0"
set ip_disp "SatCat5 4-Wire UART PHY"
set ip_desc "Mixed-media Ethernet-over-UART port with four-wire flow control."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_serial_uart_4wire.vhd

# Connect I/O ports
ipcore_add_gpio txd
ipcore_add_gpio rxd
ipcore_add_gpio cts_n
ipcore_add_gpio rts_n
ipcore_add_ethport Eth sw master
ipcore_add_clock refclk Eth
ipcore_add_reset reset_p ACTIVE_HIGH
ipcore_add_cfgopt Cfg cfg

# Set parameters
ipcore_add_param CLKREF_HZ long 100000000 \
    {Frequency of "refclk" signal (Hz)}
ipcore_add_param BAUD_HZ long 921600 \
    {Default UART baud rate (Hz)}

# Package the IP-core.
ipcore_finished
