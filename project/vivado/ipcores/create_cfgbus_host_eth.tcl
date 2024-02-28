# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_host_eth
#

# Create a basic IP-core project.
set ip_name "cfgbus_host_eth"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus Host (Ethernet)"
set ip_desc "Virtual Ethernet port for controlling ConfigBus peripherals."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_cfgbus_host_eth.vhd

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg master
ipcore_add_ethport Eth sw master
ipcore_add_irq irq_out
ipcore_add_clock sys_clk Eth
ipcore_add_reset reset_p ACTIVE_HIGH

# Set parameters
ipcore_add_param CFG_ETYPE      hexstring {5C01} \
    {EtherType for ConfigBus commands (hex)}
ipcore_add_param CFG_MACADDR    hexstring {5A5ADEADBEEF} \
    {Local MAC address (hex)}
ipcore_add_param MIN_FRAME      long 64 \
    {Minimum outgoing frame size (total bytes including FCS)}
ipcore_add_param RD_TIMEOUT     long 16 \
    {ConfigBus read timeout (clock cycles)}

# Package the IP-core.
ipcore_finished
