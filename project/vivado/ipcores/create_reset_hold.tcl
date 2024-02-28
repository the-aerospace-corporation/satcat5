# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.reset_hold
#

# Create a basic IP-core project.
set ip_name "reset_hold"
set ip_vers "1.0"
set ip_disp "SatCat5 Reset Generator"
set ip_desc "Reset for at least N clock cycles."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/common_*.vhd
ipcore_add_top  $ip_root/wrap_reset_hold.vhd

# Create each of the I/O ports
ipcore_add_reset aresetp ACTIVE_HIGH
ipcore_add_reset aresetn ACTIVE_LOW
ipcore_add_reset reset_p ACTIVE_HIGH master
ipcore_add_reset reset_n ACTIVE_LOW master
ipcore_add_clock clk {reset_p reset_n}

# Set parameters
ipcore_add_param RESET_HIGH bool false \
    {Active-high polarity for the input signal?}
ipcore_add_param RESET_HOLD long 100000 \
    {Minimum reset duration, in clock cycles}

# Enable one of the two inputs based on RESET_HIGH setting.
set_property enablement_dependency {$RESET_HIGH} [ipx::get_bus_interfaces aresetp -of_objects $ip]
set_property enablement_dependency {!$RESET_HIGH} [ipx::get_bus_interfaces aresetn -of_objects $ip]

# Package the IP-core.
ipcore_finished
