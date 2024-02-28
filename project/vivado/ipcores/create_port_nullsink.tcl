# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.port_nullsink
#

# Create a basic IP-core project.
set ip_name "port_nullsink"
set ip_vers "1.0"
set ip_disp "SatCat5 Null-sink Port"
set ip_desc "SatCat5 adapter for capped-off or empty ports."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_nullsink.vhd

# Connect everything except the RGMII port.
ipcore_add_ethport Eth sw master
ipcore_add_clock refclk {}
ipcore_add_reset reset_p ACTIVE_HIGH

# Package the IP-core.
ipcore_finished
