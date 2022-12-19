# ------------------------------------------------------------------------
# Copyright 2020, 2021, 2022 The Aerospace Corporation
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
# This script packages a Vivado IP core: satcat5.port_axi_mailbox
#
# Note: This core is provided for backwards compatibility, but may be removed
#       in a future release.  Please use "cfgbus_host_axi" + "port_mailbox".

# Create a basic IP-core project.
set ip_name "port_axi_mailbox"
set ip_vers "1.0"
set ip_disp "SatCat5 AXI4-Mailbox (Virtual PHY)"
set ip_desc "Virtual Ethernet port suitable for microcontroller polling via AXI4-Lite with a single-register interface."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_axi_mailbox.vhd

# Connect I/O ports
ipcore_add_axilite CtrlAxi axi_clk axi_aresetn axi
ipcore_add_ethport Eth sw master
ipcore_add_refopt PtpRef tref
ipcore_add_irq irq_out

# Set parameters
ipcore_add_param ADDR_WIDTH long 32 \
    {Bits in AXI address word}
ipcore_add_param MIN_FRAME long 64 \
    {Minimum outgoing frame length. (Total bytes including actual or implied FCS.) Shorter frames will be zero-padded as needed.}
ipcore_add_param APPEND_FCS bool true \
    {Append frame check sequence (FCS / CRC32) to outgoing packets? (Recommended)}
ipcore_add_param STRIP_FCS bool true \
    {Remove frame check sequence (FCS / CRC32) from incoming packets? (Recommended)}

# Package the IP-core.
ipcore_finished
