# ------------------------------------------------------------------------
# Copyright 2022 The Aerospace Corporation
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
# This script packages a Vivado IP core: satcat5.ptp_reference
#

# Create a basic IP-core project.
set ip_name "ptp_reference"
set ip_vers "1.0"
set ip_disp "SatCat5 PTP Time Reference (Vernier clock)"
set ip_desc "Generate a Vernier clock-pair and reference counter, with optional ConfigBus control."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/cfgbus_common.vhd
ipcore_add_file $src_dir/common/common_functions.vhd
ipcore_add_file $src_dir/common/common_primitives.vhd
ipcore_add_file $src_dir/common/eth_frame_common.vhd
ipcore_add_file $src_dir/common/ptp_counter_gen.vhd
ipcore_add_file $src_dir/common/ptp_types.vhd
ipcore_add_top  $ip_root/wrap_ptp_reference.vhd

# Connect I/O ports
ipcore_add_reftime PtpRef tref master
ipcore_add_cfgopt Cfg cfg
ipcore_add_clock ref_clk PtpRef
ipcore_add_reset reset_p ACTIVE_HIGH

# Set parameters
ipcore_add_param PTP_REF_HZ long 100000000 \
    {Frequency of "ref_clk", measured in Hz.}

# Package the IP-core.
ipcore_finished
