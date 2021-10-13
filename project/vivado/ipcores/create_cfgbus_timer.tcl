# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation
#
# This file is part of SatCat5.
#
# SatCat5 is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# SatCat5 is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_timer
#

# Create a basic IP-core project.
set ip_name "cfgbus_timer"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus Timer"
set ip_desc "Time counter, fixed-interval timer, watchdog timer, and external event timing."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     cfgbus_common.vhd
ipcore_add_file $src_dir/common     cfgbus_timer.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_sync $src_dir/xilinx     $part_family
ipcore_add_top  $ip_root            wrap_cfgbus_timer

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg slave
ipcore_add_gpio wdog_resetp
ipcore_add_gpio ext_evt_in

# Set parameters
ipcore_add_param DEV_ADDR devaddr 0
ipcore_add_param CFG_CLK_HZ long 100000000
ipcore_add_param EVT_ENABLE bool true
ipcore_add_param EVT_RISING bool true
ipcore_add_param TMR_ENABLE bool true
ipcore_add_param WDOG_PAUSE bool true

# Enable/disable ports depending on configuration.
set_property driver_value 0 [ipx::get_ports ext_evt_in -of_objects $ip]
set_property enablement_dependency {$EVT_ENABLE} [ipx::get_ports ext_evt_in -of_objects $ip]
set_property enablement_tcl_expr {$EVT_ENABLE} [ipx::get_user_parameters EVT_RISING -of_objects $ip]

# Package the IP-core.
ipcore_finished
