# ------------------------------------------------------------------------
# Copyright 2022-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.ptp_reference
#

# Create a basic IP-core project.
set ip_name "ptp_reference"
set ip_vers "1.0"
set ip_disp "SatCat5 PTP Time Reference (Vernier clock)"
set ip_desc "Generate a Vernier clock-pair and reference counter, with optional ConfigBus control."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
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
