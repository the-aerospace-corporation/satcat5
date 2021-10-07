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
# This script packages a Vivado IP core: satcat5.cfgbus_host_uart
#

# Create a basic IP-core project.
set ip_name "cfgbus_host_uart"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus Host (UART)"
set ip_desc "UART port for controlling ConfigBus peripherals."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename
ipcore_add_file $src_dir/common     cfgbus_common.vhd
ipcore_add_file $src_dir/common     cfgbus_host_eth.vhd
ipcore_add_file $src_dir/common     cfgbus_host_uart.vhd
ipcore_add_file $src_dir/common     common_functions.vhd
ipcore_add_file $src_dir/common     common_primitives.vhd
ipcore_add_file $src_dir/common     eth_frame_adjust.vhd
ipcore_add_file $src_dir/common     eth_frame_check.vhd
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     fifo_packet.vhd
ipcore_add_file $src_dir/common     fifo_smol_async.vhd
ipcore_add_file $src_dir/common     fifo_smol_resize.vhd
ipcore_add_file $src_dir/common     fifo_smol_sync.vhd
ipcore_add_file $src_dir/common     io_uart.vhd
ipcore_add_file $src_dir/common     slip_decoder.vhd
ipcore_add_file $src_dir/common     slip_encoder.vhd
ipcore_add_top  $ip_root            wrap_cfgbus_host_uart

# Connect I/O ports
ipcore_add_gpio uart_txd
ipcore_add_gpio uart_rxd
ipcore_add_cfgbus Cfg cfg master
ipcore_add_clock sys_clk {}
ipcore_add_reset reset_p ACTIVE_HIGH

# Set parameters
ipcore_add_param CFG_ETYPE      hexstring {5C01}
ipcore_add_param CFG_MACADDR    hexstring {5A5ADEADBEEF}
ipcore_add_param CLKREF_HZ      long 100000000
ipcore_add_param UART_BAUD_HZ   long 921600
ipcore_add_param RD_TIMEOUT     long 16

# Package the IP-core.
ipcore_finished
