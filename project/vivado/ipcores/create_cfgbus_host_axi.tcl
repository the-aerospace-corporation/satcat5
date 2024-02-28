# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.cfgbus_host_axi
#

# Create a basic IP-core project.
set ip_name "cfgbus_host_axi"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus Host (AXI4-Lite)"
set ip_desc "Adapter for controlling ConfigBus peripherals using AXI-Lite"

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_cfgbus_host_axi.vhd

# Connect I/O ports
# Note: Request 256 ConfigBus devices = 1 Mbyte memory-map.
# TODO: Set BASE_ADDR to avoid address-mangling if user sets a smaller range.
ipcore_add_axilite CtrlAxi axi_clk axi_aresetn axi "1M"
ipcore_add_cfgbus Cfg cfg master
ipcore_add_irq irq_out

# Set parameters
ipcore_add_param ADDR_WIDTH long 32 \
    {Bits in AXI address word}
ipcore_add_param RD_TIMEOUT long 16 \
    {Timeout for ConfigBus reads (clock cycles)}

# Package the IP-core.
ipcore_finished
