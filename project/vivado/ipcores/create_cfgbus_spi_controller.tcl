# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_spi_controller
#

# Create a basic IP-core project.
set ip_name "cfgbus_spi_controller"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus SPI Controller"
set ip_desc "Controller for a 4-wire SPI interface."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_cfgbus_spi_controller.vhd

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg slave
ipcore_add_gpio spi_csb
ipcore_add_gpio spi_sck
ipcore_add_gpio spi_sdo
ipcore_add_gpio spi_sdi
set dcx [ipcore_add_gpio dcx_out]

# Set parameters
ipcore_add_param DEV_ADDR devaddr 0 \
    {ConfigBus device address (0-255)}
ipcore_add_param DCX_COUNT long 0 \
    {Enable DCX output? Held low for first N bytes of each transfer.}
set_property enablement_dependency "\$DCX_COUNT > 0" $dcx

# Package the IP-core.
ipcore_finished
