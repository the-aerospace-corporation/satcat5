# ------------------------------------------------------------------------
# Copyright 2020, 2021 The Aerospace Corporation
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
# This script packages a Vivado IP core: satcat5.switch_aux
#

# Create a basic IP-core project.
set ip_name "switch_aux"
set ip_vers "1.0"
set ip_disp "SatCat5 Auxiliary Support"
set ip_desc "Error-reporting for SatCat5 switches and FPGA configuration scrubbing."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Generate IP for the configuration-scrubbing IP-core.
# (Instantiation is optional, controlled by build-time generic.)
source $ip_root/../generate_sem.tcl
generate_sem sem_0
ipcore_add_xci sem_0

# Add all required source files:
#               Path                Filename/Part Family
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     fifo_smol_async.vhd
ipcore_add_file $src_dir/common     fifo_smol_sync.vhd
ipcore_add_file $src_dir/common     io_error_reporting.vhd
ipcore_add_file $src_dir/common     io_leds.vhd
ipcore_add_file $src_dir/common     io_text_lcd.vhd
ipcore_add_file $src_dir/common     io_uart.vhd
ipcore_add_file $src_dir/common     switch_aux.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_file $src_dir/xilinx     scrub_xilinx.vhd
ipcore_add_sync $src_dir/xilinx     $part_family
ipcore_add_top  $ip_root            wrap_switch_aux

# Connect all the basic I/O ports
ipcore_add_clock scrub_clk {}
ipcore_add_reset reset_p ACTIVE_HIGH
ipcore_add_gpio scrub_req_t
ipcore_add_gpio status_uart

# Connec the Text-LCD control port
set intf [ipx::add_bus_interface text_lcd $ip]
set_property abstraction_type_vlnv aero.org:satcat5:TextLCD_rtl:1.0 $intf
set_property bus_type_vlnv aero.org:satcat5:TextLCD:1.0 $intf
set_property interface_mode master $intf
set_property physical_name text_lcd_db  [ipx::add_port_map "lcd_db" $intf]
set_property physical_name text_lcd_e   [ipx::add_port_map "lcd_e"  $intf]
set_property physical_name text_lcd_rw  [ipx::add_port_map "lcd_rw" $intf]
set_property physical_name text_lcd_rs  [ipx::add_port_map "lcd_rs" $intf]

# Set parameters
ipcore_add_param SCRUB_CLK_HZ long 100000000
ipcore_add_param SCRUB_ENABLE bool false
ipcore_add_param STARTUP_MSG string "SatCat5 READY!"
ipcore_add_param UART_BAUD long 921600
set ccount [ipcore_add_param CORE_COUNT long 1]

# Set min/max range on the CORE_COUNT parameter.
set CORE_COUNT_MAX 12
set_property value_validation_type range_long $ccount
set_property value_validation_range_minimum 1 $ccount
set_property value_validation_range_maximum $CORE_COUNT_MAX $ccount

# Add each of the error-vector ports with logic to show/hide.
# (HDL always has CORE_COUNT_MAX, enable first N depending on GUI setting.)
for {set idx 0} {$idx < $CORE_COUNT_MAX} {incr idx} {
    set name [format "errvec_%02d" $idx]
    set intf [ipcore_add_gpio $name]
    set_property enablement_dependency "$idx < \$CORE_COUNT" $intf
    set_property driver_value 0 $intf
}

# Package the IP-core.
ipcore_finished
