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
# This script packages a Vivado IP core: satcat5.port_nullsink
#

# Create a basic IP-core project.
set ip_name "port_nullsink"
set ip_vers "1.0"
set ip_disp "SatCat5 Null-sink Port"
set ip_desc "SatCat5 adapter for capped-off or empty."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
#               Path                Filename
ipcore_add_file $src_dir/common     eth_frame_common.vhd
ipcore_add_file $src_dir/common     port_nullsink.vhd
ipcore_add_file $src_dir/common     switch_types.vhd
ipcore_add_top  $ip_root            wrap_port_nullsink

# Connect everything except the RGMII port.
ipcore_add_ethport Eth sw master
ipcore_add_clock refclk {}
ipcore_add_reset reset_p ACTIVE_HIGH

# Package the IP-core.
ipcore_finished
