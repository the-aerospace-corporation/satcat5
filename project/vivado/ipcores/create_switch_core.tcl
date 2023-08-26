# ------------------------------------------------------------------------
# Copyright 2020, 2021, 2022, 2023 The Aerospace Corporation
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
# This script packages a Vivado IP core: satcat5.switch_core
#

# Create a basic IP-core project.
set ip_name "switch_core"
set ip_vers "1.0"
set ip_disp "SatCat5 N-Port Ethernet Switch"
set ip_desc "SatCat5 general-purpose Layer-2 Ethernet Switch."

variable ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_switch_core.vhd

# Connect all the basic I/O ports
ipcore_add_clock core_clk {}
ipcore_add_reset reset_p ACTIVE_HIGH
ipcore_add_gpio scrub_req_t
ipcore_add_gpio errvec_t
ipcore_add_cfgopt Cfg cfg

# Set parameters
set pcount [ipcore_add_param PORT_COUNT long 3 \
    {Number of attached Ethernet ports (standard)}]
set xcount [ipcore_add_param PORTX_COUNT long 0 \
    {Number of attached Ethernet ports (10-gigabit)}]
set dwidth [ipcore_add_param DATAPATH_BYTES long 3 \
    {Width of datapath. Max aggregate throughput is DATAPATH_BYTES x CORE_CLK_HZ x 8 Mbps}]
ipcore_add_param STATS_ENABLE bool false \
    {Enable throughput and packet-count statistics for each port?}
ipcore_add_param STATS_DEVADDR devaddr 1 \
    {ConfigBus device address for statistics module}
ipcore_add_param CORE_CLK_HZ long 200000000 \
    {Frequency of "core_clk" signal (Hz)}
ipcore_add_param SUPPORT_PAUSE bool true \
    {Include support for IEEE 802.3x "pause" frames? (Recommended)}
ipcore_add_param SUPPORT_PTP bool false \
    {Reserved for future expansion, not currently supported.}
ipcore_add_param SUPPORT_VLAN bool false \
    {Include support for IEEE 802.1Q Virtual Local Area Networks?}
ipcore_add_param MISS_BCAST bool true \
    {Should frames with an uncached destination MAC be broadcast (true) or dropped (false)?}
ipcore_add_param ALLOW_JUMBO bool false \
    {Allow Ethernet frames with a length longer than 1522 bytes? (Total including FCS)}
ipcore_add_param ALLOW_RUNT bool false \
    {Allow Ethernet frames witha  length shorter than 64 bytes? (Total including FCS)}
ipcore_add_param ALLOW_PRECOMMIT bool false \
    {Allow output FIFO cut-through? (Slightly reduced latency)}
ipcore_add_param IBUF_KBYTES long 2 \
    {Size of each port's input buffer, in kilobytes}
ipcore_add_param HBUF_KBYTES long 0 \
    {Size of each port's high-priority output buffer, in kilobytes (0 = disabled)}
ipcore_add_param OBUF_KBYTES long 6 \
    {Size of each port's output buffer, in kilobytes}
ipcore_add_param PTP_MIXED_STEP bool true \
    {Support PTP two-step conversion? (One-step vs two-step mode on different ports.)}
ipcore_add_param MAC_TABLE_EDIT bool true \
    {Allow manual read/write of the MAC-address cache?}
ipcore_add_param MAC_TABLE_SIZE long 64 \
    {Size of the MAC-address cache}

# Set min/max range on the DATAPATH_BYTES parameter.
set_property value_validation_type range_long $dwidth
set_property value_validation_range_minimum 1 $dwidth
set_property value_validation_range_maximum 6 $dwidth

# Set min/max range on the PORT_COUNT parameter.
set PORT_COUNT_MAX 32
set_property value_validation_type range_long $pcount
set_property value_validation_range_minimum 0 $pcount
set_property value_validation_range_maximum $PORT_COUNT_MAX $pcount

set PORTX_COUNT_MAX 8
set_property value_validation_type range_long $xcount
set_property value_validation_range_minimum 0 $xcount
set_property value_validation_range_maximum $PORTX_COUNT_MAX $xcount

# Enable ports and parameters depending on configuration.
set_property enablement_dependency {$CFG_ENABLE || $STATS_ENABLE} [ipx::get_bus_interfaces Cfg -of_objects $ip]
set_property enablement_tcl_expr {$STATS_ENABLE} [ipx::get_user_parameters STATS_DEVADDR -of_objects $ip]
set_property enablement_tcl_expr {$SUPPORT_PTP} [ipx::get_user_parameters PTP_MIXED_STEP -of_objects $ip]
set_property enablement_tcl_expr {$CFG_ENABLE} [ipx::get_user_parameters MAC_TABLE_EDIT -of_objects $ip]

# Add each of the Ethernet ports with logic to show/hide.
# (HDL always has PORT_COUNT_MAX, enable first N depending on GUI setting.)
for {set idx 0} {$idx < $PORT_COUNT_MAX} {incr idx} {
    set name [format "Port%02d" $idx]
    set port [format "p%02d" $idx]
    set intf [ipcore_add_ethport $name $port slave]
    set_property enablement_dependency "$idx < \$PORT_COUNT" $intf
}

for {set idx 0} {$idx < $PORTX_COUNT_MAX} {incr idx} {
    set name [format "PortX%02d" $idx]
    set port [format "x%02d" $idx]
    set intf [ipcore_add_xgeport $name $port slave]
    set_property enablement_dependency "$idx < \$PORTX_COUNT" $intf
}

# Package the IP-core.
ipcore_finished
