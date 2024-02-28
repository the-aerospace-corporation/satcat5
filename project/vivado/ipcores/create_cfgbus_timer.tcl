# ------------------------------------------------------------------------
# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_timer
#

# Create a basic IP-core project.
set ip_name "cfgbus_timer"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus Timer"
set ip_desc "Time counter, fixed-interval timer, watchdog timer, and external event timing."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_cfgbus_timer.vhd

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg slave
ipcore_add_reset wdog_resetp ACTIVE_HIGH master
ipcore_add_gpio ext_evt_in

# Set parameters
ipcore_add_param DEV_ADDR devaddr 0 \
    {ConfigBus device address (0-255)}
ipcore_add_param CFG_CLK_HZ long 100000000 \
    {Frequency of ConfigBus clock (Hz)}
ipcore_add_param EVT_ENABLE bool true \
    {Enable event-detection timestamps?}
ipcore_add_param EVT_RISING bool true \
    {Trigger on rising edge of "ext_evt_in"?}
ipcore_add_param TMR_ENABLE bool true \
    {Enable fixed-interval timer interrupts? (Recommended)}
ipcore_add_param WDOG_PAUSE bool true \
    {Allow watchdog timer to be paused?}

# Enable/disable ports depending on configuration.
set_property driver_value 0 [ipx::get_ports ext_evt_in -of_objects $ip]
set_property enablement_dependency {$EVT_ENABLE} [ipx::get_ports ext_evt_in -of_objects $ip]
set_property enablement_tcl_expr {$EVT_ENABLE} [ipx::get_user_parameters EVT_RISING -of_objects $ip]

# Package the IP-core.
ipcore_finished
