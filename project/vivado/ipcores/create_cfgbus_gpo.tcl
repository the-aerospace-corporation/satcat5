# ------------------------------------------------------------------------
# Copyright 2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_gpo
#

# Create a basic IP-core project.
set ip_name "cfgbus_gpo"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus General-purpose output (GPO)"
set ip_desc "ConfigBus-controlled output register."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_cfgbus_gpo.vhd

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg slave
ipcore_add_gpio gpo_out

# Set parameters
ipcore_add_param DEV_ADDR devaddr 0 \
    {ConfigBus device address (0-255)}
ipcore_add_param GPO_WIDTH long 32 \
    {Number of output pins (1 - 32)}

# Package the IP-core.
ipcore_finished
