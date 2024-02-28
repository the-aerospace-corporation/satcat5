# ------------------------------------------------------------------------
# Copyright 2023-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_gpi
#

# Create a basic IP-core project.
set ip_name "cfgbus_gpi"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus General-purpose input (GPI)"
set ip_desc "ConfigBus-controlled input register."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_cfgbus_gpi.vhd

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg slave
ipcore_add_gpio gpi_in

# Set parameters
ipcore_add_param DEV_ADDR devaddr 0 \
    {ConfigBus device address (0-255)}
ipcore_add_param GPI_WIDTH long 32 \
    {Number of input pins (1 - 32)}

# Package the IP-core.
ipcore_finished
