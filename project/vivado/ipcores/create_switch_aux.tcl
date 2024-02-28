# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.switch_aux
#

# Create a basic IP-core project.
set ip_name "switch_aux"
set ip_vers "1.0"
set ip_disp "SatCat5 Auxiliary Support"
set ip_desc "Error-reporting for SatCat5 switches and FPGA configuration scrubbing."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Generate IP for the configuration-scrubbing IP-core, 7-series only.
# (Instantiation is optional, controlled by build-time generic.)
if {$part_family == "7series"} {
    source $ip_root/../generate_sem.tcl
    generate_sem sem_0
    ipcore_add_xci sem_0
}

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_file $src_dir/xilinx/scrub_xilinx.vhd
ipcore_add_top  $ip_root/wrap_switch_aux.vhd

# Connect I/O ports
ipcore_add_clock scrub_clk {}
ipcore_add_reset reset_p ACTIVE_HIGH
ipcore_add_gpio scrub_req_t
ipcore_add_gpio status_uart
ipcore_add_textlcd text_lcd text

# Set parameters
ipcore_add_param SCRUB_CLK_HZ long 100000000\
    {Frequency of "scrub_clk" in Hz}
ipcore_add_param SCRUB_ENABLE bool false\
    {Enable Soft Error Mitigation core? (7-series only)}\
    [expr {$part_family == "7series"}]
ipcore_add_param STARTUP_MSG string "SatCat5 READY!"\
    {Startup message for LCD and UART}
ipcore_add_param UART_BAUD long 921600\
    {Baud rate for status UART (Hz)}
set ccount [ipcore_add_param CORE_COUNT long 1\
    {Number of attached "switch_core" blocks}]

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

# Disable spurious warnings in the parent project.
set_msg_config -id {[Common 17-55]} -new_severity INFO -string "dont_touch.xdc"
