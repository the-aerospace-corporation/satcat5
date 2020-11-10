# Copyright 2019 The Aerospace Corporation
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

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test control}
add wave -noupdate /router_arp_update_tb/test_idx
add wave -noupdate /router_arp_update_tb/rate_in
add wave -noupdate /router_arp_update_tb/rate_out
add wave -noupdate /router_arp_update_tb/query_start
add wave -noupdate /router_arp_update_tb/query_type
add wave -noupdate /router_arp_update_tb/query_busy
add wave -noupdate -radix hexadecimal /router_arp_update_tb/query_sha
add wave -noupdate -radix hexadecimal /router_arp_update_tb/query_spa
add wave -noupdate -radix hexadecimal /router_arp_update_tb/query_tha
add wave -noupdate -radix hexadecimal /router_arp_update_tb/query_tpa
add wave -noupdate /router_arp_update_tb/rcvd_rdy
add wave -noupdate -radix hexadecimal /router_arp_update_tb/rcvd_ip
add wave -noupdate -radix hexadecimal /router_arp_update_tb/rcvd_mac
add wave -noupdate -divider {Network port}
add wave -noupdate -radix hexadecimal /router_arp_update_tb/pkt_rx_data
add wave -noupdate /router_arp_update_tb/pkt_rx_last
add wave -noupdate /router_arp_update_tb/pkt_rx_write
add wave -noupdate -divider {Update port}
add wave -noupdate -radix hexadecimal /router_arp_update_tb/update_addr
add wave -noupdate /router_arp_update_tb/update_first
add wave -noupdate /router_arp_update_tb/update_valid
add wave -noupdate /router_arp_update_tb/update_ready
add wave -noupdate /router_arp_update_tb/p_update/bcount
add wave -noupdate -divider Pre-parser
add wave -noupdate -radix hexadecimal /router_arp_update_tb/arp_rx_data
add wave -noupdate /router_arp_update_tb/arp_rx_first
add wave -noupdate /router_arp_update_tb/arp_rx_last
add wave -noupdate /router_arp_update_tb/arp_rx_write
add wave -noupdate -divider {UUT Internals}
add wave -noupdate /router_arp_update_tb/uut/cmd_state
add wave -noupdate /router_arp_update_tb/uut/cmd_busy
add wave -noupdate -radix hexadecimal /router_arp_update_tb/uut/cmd_addr
add wave -noupdate /router_arp_update_tb/uut/cmd_first
add wave -noupdate /router_arp_update_tb/uut/cmd_valid
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {999635 ns} 0}
configure wave -namecolwidth 282
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {1050 us}
