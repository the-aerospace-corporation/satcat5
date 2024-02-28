# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_uart
#

# Create a basic IP-core project.
set ip_name "cfgbus_uart"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus UART"
set ip_desc "Controller for a generic UART interface."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_cfgbus_uart.vhd

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg slave
ipcore_add_gpio uart_txd
ipcore_add_gpio uart_rxd

# Set parameters
ipcore_add_param DEV_ADDR devaddr 0 \
    {ConfigBus device address (0-255)}

# Package the IP-core.
ipcore_finished
