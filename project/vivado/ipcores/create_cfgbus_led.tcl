# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_led
#

# Create a basic IP-core project.
set ip_name "cfgbus_led"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus LED-PWM Controller"
set ip_desc "Multichannel PWM controller for LEDs."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_cfgbus_led.vhd

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg slave
ipcore_add_gpio led_out

# Set parameters
ipcore_add_param DEV_ADDR devaddr 0 \
    {ConfigBus device address (0-255)}
ipcore_add_param LED_COUNT long 4 \
    {Number of PWM/LED drivers}
ipcore_add_param LED_POL bool true \
    {Are LEDs active-high (true) or active-low (false)?}

# Package the IP-core.
ipcore_finished
