# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script packages a Vivado IP core: satcat5.port_status_inline
#

# Create a basic IP-core project.
set ip_name "port_inline_status"
set ip_vers "1.0"
set ip_disp "SatCat5 Inline Status/Keep-Alive"
set ip_desc "Inline port adapter that injects status or keep-alive messages."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_inline_status.vhd

# Connect I/O ports
ipcore_add_ethport LocalPort lcl master
ipcore_add_ethport NetPort net slave
ipcore_add_gpio status_val
ipcore_add_gpio status_wr_t

# Set parameters
ipcore_add_param SEND_EGRESS        bool true \
    {Send status packets to NetPort?}
ipcore_add_param SEND_INGRESS       bool true \
    {Send status packets to LocalPort?}
ipcore_add_param MSG_BYTES          long 0 \
    {Length of status word, in bytes}
ipcore_add_param MSG_ETYPE          hexstring {5C00} \
    {EtherType for the status message (hex)}
ipcore_add_param MAC_DEST           hexstring {FFFFFFFFFFFF} \
    {Destination address for the status message (hex)}
ipcore_add_param MAC_SOURCE         hexstring {5A5ADEADBEEF} \
    {Source address for the status message (hex)}
ipcore_add_param AUTO_DELAY_CLKS    long 125000000 \
    {Send status message every N clocks, or zero to disable.}
ipcore_add_param MIN_FRAME_BYTES    long 64 \
    {Zero-pad status message to a minimum length. (Total bytes including FCS.)}

# Enable ports and parameters depending on configuration.
set_property enablement_dependency {$MSG_BYTES > 0} [ipx::get_ports status_val -of_objects $ip]
set_property enablement_dependency {$AUTO_DELAY_CLKS = 0} [ipx::get_ports status_wr_t -of_objects $ip]

# Package the IP-core.
ipcore_finished
