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
add wave -noupdate /router_arp_cache_tb/test_index
add wave -noupdate /router_arp_cache_tb/test_rate
add wave -noupdate /router_arp_cache_tb/query_start
add wave -noupdate /router_arp_cache_tb/update_start
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/send_query_ip
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/send_update_ip
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/send_update_mac
add wave -noupdate /router_arp_cache_tb/rcvd_reply_ok
add wave -noupdate /router_arp_cache_tb/rcvd_reply_match
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/rcvd_reply_mac
add wave -noupdate /router_arp_cache_tb/rcvd_request_ok
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/rcvd_request_ip
add wave -noupdate -divider {UUT I/O}
add wave -noupdate /router_arp_cache_tb/query_start
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/query_addr
add wave -noupdate /router_arp_cache_tb/query_first
add wave -noupdate /router_arp_cache_tb/query_valid
add wave -noupdate /router_arp_cache_tb/query_ready
add wave -noupdate /router_arp_cache_tb/reply_match
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/reply_addr
add wave -noupdate /router_arp_cache_tb/reply_first
add wave -noupdate /router_arp_cache_tb/reply_write
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/request_addr
add wave -noupdate /router_arp_cache_tb/request_first
add wave -noupdate /router_arp_cache_tb/request_write
add wave -noupdate /router_arp_cache_tb/update_start
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/update_addr
add wave -noupdate /router_arp_cache_tb/update_first
add wave -noupdate /router_arp_cache_tb/update_valid
add wave -noupdate /router_arp_cache_tb/update_ready
add wave -noupdate -divider {UUT internals}
add wave -noupdate /router_arp_cache_tb/uut/query_state
add wave -noupdate /router_arp_cache_tb/uut/query_mask
add wave -noupdate /router_arp_cache_tb/uut/query_tfound
add wave -noupdate -radix unsigned /router_arp_cache_tb/uut/query_taddr
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/uut/tbl_rd_val
add wave -noupdate /router_arp_cache_tb/uut/write_next
add wave -noupdate /router_arp_cache_tb/uut/write_state
add wave -noupdate /router_arp_cache_tb/uut/write_mask
add wave -noupdate /router_arp_cache_tb/uut/write_tfound
add wave -noupdate /router_arp_cache_tb/uut/write_tevict
add wave -noupdate -radix unsigned /router_arp_cache_tb/uut/write_taddr
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/uut/camwr_addr
add wave -noupdate /router_arp_cache_tb/uut/camwr_mask
add wave -noupdate /router_arp_cache_tb/uut/camwr_en
add wave -noupdate /router_arp_cache_tb/uut/tbl_wr_en
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/uut/tbl_wr_val
add wave -noupdate -radix hexadecimal /router_arp_cache_tb/uut/tbl_wr_old
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {999095 ns} 0}
configure wave -namecolwidth 294
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
