# ------------------------------------------------------------------------
# Copyright 2021, 2022 The Aerospace Corporation
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
# This script packages a Vivado IP core: satcat5.cfgbus_host_axi
#

# Create a basic IP-core project.
set ip_name "cfgbus_host_axi"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus Host (AXI4-Lite)"
set ip_desc "Adapter for controlling ConfigBus peripherals using AXI-Lite"

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/cfgbus_common.vhd
ipcore_add_file $src_dir/common/cfgbus_host_axi.vhd
ipcore_add_file $src_dir/common/common_functions.vhd
ipcore_add_file $src_dir/common/common_primitives.vhd
ipcore_add_file $src_dir/common/fifo_smol_sync.vhd
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
