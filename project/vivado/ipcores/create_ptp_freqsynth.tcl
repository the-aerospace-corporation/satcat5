# ------------------------------------------------------------------------
# Copyright 2022-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.ptp_freqsynth
#

# Create a basic IP-core project.
set ip_name "ptp_freqsynth"
set ip_vers "1.0"
set ip_disp "SatCat5 PTP frequency synthesizer"
set ip_desc "Generate a psuedo-clock (e.g., 1 Hz, 10 MHz) referenced to a real-time clock."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_file $src_dir/xilinx/sgmii_serdes_tx.vhd
ipcore_add_top  $ip_root/wrap_ptp_freqsynth.vhd

# Connect I/O ports
ipcore_add_ptptime RtcRef rtc monitor
ipcore_add_clock rtc_clk_5x {}
ipcore_add_reset reset_p ACTIVE_HIGH

# Synthesized output "clock"
# Note: Does Xilinx define a generic LVDS pair?  Not a clock, can't use "diff_clock".
ipcore_add_gpio synth_txp
ipcore_add_gpio synth_txn

# Set parameters
ipcore_add_param RTC_CLK_HZ long 125000000 \
    {RTC reference frequency, measured in Hz. "rtc_clk_5x" must be five times this frequency.}
ipcore_add_param SYNTH_HZ long 10000000 \
    {Synthesized output frequency, measured in Hz.}
ipcore_add_param SYNTH_IOSTD string "LVDS_25" \
    {I/O standard for synthesized signal.}

# Package the IP-core.
ipcore_finished
