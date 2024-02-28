# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.port_adapter
#

# Create a basic IP-core project.
set ip_name "port_adapter"
set ip_vers "1.0"
set ip_disp "SatCat5 Runt-packet Adapter"
set ip_desc "Runt-packet adapter that zero-pads outgoing packets to the specified minimum length."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_adapter.vhd

# Connect I/O ports
ipcore_add_ethport SwPort sw master
ipcore_add_ethport MacPort mac slave

# Package the IP-core.
ipcore_finished
