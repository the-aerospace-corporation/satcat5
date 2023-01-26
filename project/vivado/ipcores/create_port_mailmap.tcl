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
# This script packages a Vivado IP core: satcat5.port_axi_mailmap
#

# Create a basic IP-core project.
set ip_name "port_mailmap"
set ip_vers "1.0"
set ip_disp "SatCat5 ConfigBus MailMap (Virtual PHY)"
set ip_desc "Virtual Ethernet port suitable for microcontroller polling via ConfigBus with a memory-mapped interface."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_mailmap.vhd

# Connect I/O ports
ipcore_add_cfgbus Cfg cfg slave
ipcore_add_ethport Eth sw master
ipcore_add_refopt PtpRef tref
set rtc [ipcore_add_ptptime PtpTime rtc master]

# Set parameters
ipcore_add_param DEV_ADDR devaddr 0 \
    {ConfigBus device address (0-255)}
ipcore_add_param MIN_FRAME long 64 \
    {Minimum outgoing frame length. (Total bytes including actual or implied FCS.) Shorter frames will be zero-padded as needed.}
ipcore_add_param APPEND_FCS bool true \
    {Append frame check sequence (FCS / CRC32) to outgoing packets? (Recommended)}
ipcore_add_param STRIP_FCS bool true \
    {Remove frame check sequence (FCS / CRC32) from incoming packets? (Recommended)}
set_property enablement_dependency {$PTP_ENABLE} $rtc

# Package the IP-core.
ipcore_finished
