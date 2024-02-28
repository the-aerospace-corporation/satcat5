# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_host_uart
#

# Create a basic IP-core project.
set ip_name "cfgbus_host_uart"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus Host (UART)"
set ip_desc "UART port for controlling ConfigBus peripherals."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_cfgbus_host_uart.vhd

# Connect I/O ports
ipcore_add_gpio uart_txd
ipcore_add_gpio uart_rxd
ipcore_add_cfgbus Cfg cfg master
ipcore_add_clock sys_clk {}
ipcore_add_reset reset_p ACTIVE_HIGH

# Set parameters
ipcore_add_param CFG_ETYPE      hexstring {5C01} \
    {EtherType for ConfigBus commands (hex)}
ipcore_add_param CFG_MACADDR    hexstring {5A5ADEADBEEF} \
    {Local MAC address (hex)}
ipcore_add_param CLKREF_HZ      long 100000000 \
    {Frequency of "sys_clk" in Hz}
ipcore_add_param UART_BAUD_HZ   long 921600 \
    {UART baud rate (Hz)}
ipcore_add_param RD_TIMEOUT     long 16 \
    {ConfigBus read timeout (clock cycles)}

# Package the IP-core.
ipcore_finished
