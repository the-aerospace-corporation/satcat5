# ------------------------------------------------------------------------
# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.ublaze_reset
#

# Create a basic IP-core project.
set ip_name "ublaze_reset"
set ip_vers "1.0"
set ip_disp "SatCat5 Microblaze Reset Sequencing"
set ip_desc "Drop-in replacement for the Xilinx Processing System Reset Module"

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Suppress polarity warning for "ext_reset_in".
set_msg_config -suppress -id {[IP_Flow 19-3157]}

# Add all required source files:
ipcore_add_file $src_dir/common/common_*.vhd
ipcore_add_top  $src_dir/xilinx/ublaze_reset.vhd

# Create each of the I/O ports
# Note: For compatibility with the Xilinx core, don't mark "dcm_locked" as a reset.
ipcore_add_clock slowest_sync_clk \
    {mb_reset bus_struct_reset peripheral_reset interconnect_aresetn peripheral_aresetn}
ipcore_add_reset ext_reset_in           ACTIVE_LOW slave
ipcore_add_reset aux_reset_in           ACTIVE_HIGH slave
ipcore_add_reset mb_debug_sys_rst       ACTIVE_HIGH slave
ipcore_add_gpio  dcm_locked
ipcore_add_reset mb_reset               ACTIVE_HIGH master
ipcore_add_reset bus_struct_reset       ACTIVE_HIGH master
ipcore_add_reset peripheral_reset       ACTIVE_HIGH master
ipcore_add_reset interconnect_aresetn   ACTIVE_LOW master
ipcore_add_reset peripheral_aresetn     ACTIVE_LOW master

# All outputs are synchronous to the provided clock.
ipx::associate_bus_interfaces -clock slowest_sync_clk -reset mb_reset $ip
ipx::associate_bus_interfaces -clock slowest_sync_clk -reset bus_struct_reset $ip
ipx::associate_bus_interfaces -clock slowest_sync_clk -reset peripheral_reset $ip
ipx::associate_bus_interfaces -clock slowest_sync_clk -reset interconnect_aresetn $ip
ipx::associate_bus_interfaces -clock slowest_sync_clk -reset peripheral_aresetn $ip

# Package the IP-core.
ipcore_finished
