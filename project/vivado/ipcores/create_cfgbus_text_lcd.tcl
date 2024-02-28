# ------------------------------------------------------------------------
# Copyright 2022-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_text_lcd
#

# Create a basic IP-core project.
set ip_name "cfgbus_text_lcd"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus Text-LCD"
set ip_desc "Controller for a two-line text display."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_cfgbus_text_lcd.vhd

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg slave
ipcore_add_textlcd text_lcd text

# Set parameters
ipcore_add_param DEV_ADDR devaddr 0 \
    {ConfigBus device address (0-255)}
ipcore_add_param CFG_CLK_HZ long 100000000 \
    {ConfigBus clock frequency (Hz)}
ipcore_add_param MSG_WAIT long 255 \
    {Wait time after each screen refresh (msec)}

# Package the IP-core.
ipcore_finished
