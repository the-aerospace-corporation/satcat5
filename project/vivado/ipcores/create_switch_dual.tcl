# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.switch_dual
#

# Create a basic IP-core project.
set ip_name "switch_dual"
set ip_vers "1.0"
set ip_disp "SatCat5 Dual-port Ethernet Switch"
set ip_desc "A two-port switch, typically used for interface-type adapation."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_switch_dual.vhd

# Connect I/O ports
ipcore_add_ethport "PortA" "pa" "slave"
ipcore_add_ethport "PortB" "pb" "slave"
ipcore_add_gpio errvec_t

# Set parameters
ipcore_add_param ALLOW_JUMBO bool false \
    {Allow Ethernet frames longer than 1522 bytes? (Total bytes including FCS)}
ipcore_add_param ALLOW_RUNT bool false \
    {Allow Ethernet frames shorter than 64 bytes? (Total bytes including FCS)}
ipcore_add_param OBUF_KBYTES long 2 \
    {Output buffer size, in kilobytes.}

# Package the IP-core.
ipcore_finished
