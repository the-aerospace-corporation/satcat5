# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.port_crosslink
#

# Create a basic IP-core project.
set ip_name "port_crosslink"
set ip_vers "1.0"
set ip_disp "SatCat5 Switch-to-Switch Crosslink"
set ip_desc "Crosslink for connecting two SatCat5 switch cores back-to-back."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_crosslink.vhd

# Connect I/O ports
ipcore_add_ethport PortA pa master
ipcore_add_ethport PortB pb master
ipcore_add_refopt PtpRef tref
ipcore_add_clock ref_clk {PortA PortB}
ipcore_add_reset reset_p ACTIVE_HIGH

# Set parameters
ipcore_add_param RUNT_PORTA bool false \
    {Allow frames shorter than 64 bytes on PortA?}
ipcore_add_param RUNT_PORTB bool false \
    {Allow frames shorter than 64 bytes on PortB?}
ipcore_add_param RATE_DIV long 2 \
    {Throughput limiter with maximum duty cycle = 1/N}

# Package the IP-core.
ipcore_finished
