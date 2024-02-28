# ------------------------------------------------------------------------
# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
set cfg_clk_hz [ipcore_add_param CFG_CLK_HZ long 100000000 \
    {ConfigBus clock frequency. (Required for PTP.)}]
ipcore_add_param DEV_ADDR devaddr 0 \
    {ConfigBus device address (0-255)}
ipcore_add_param MIN_FRAME long 64 \
    {Minimum outgoing frame length. (Total bytes including actual or implied FCS.) Shorter frames will be zero-padded as needed.}
ipcore_add_param APPEND_FCS bool true \
    {Append frame check sequence (FCS / CRC32) to outgoing packets? (Recommended)}
ipcore_add_param STRIP_FCS bool true \
    {Remove frame check sequence (FCS / CRC32) from incoming packets? (Recommended)}
set_property enablement_dependency {$PTP_ENABLE} $rtc
set_property enablement_tcl_expr {$PTP_ENABLE} $cfg_clk_hz

# Package the IP-core.
ipcore_finished
