# Copyright 2023 The Aerospace Corporation
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
add wave -noupdate /mac_vlan_rate_tb/test_index
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/in_vtag
add wave -noupdate /mac_vlan_rate_tb/in_nlast
add wave -noupdate /mac_vlan_rate_tb/in_write
add wave -noupdate /mac_vlan_rate_tb/uut/query_type
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/query_vtag
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/query_len
add wave -noupdate /mac_vlan_rate_tb/uut/query_sof
add wave -noupdate /mac_vlan_rate_tb/uut/scan_req
add wave -noupdate /mac_vlan_rate_tb/uut/scan_next
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/scan_addr
add wave -noupdate /mac_vlan_rate_tb/uut/scan_timer
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/query0_addr
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/query1_addr
add wave -noupdate /mac_vlan_rate_tb/uut/query0_en
add wave -noupdate /mac_vlan_rate_tb/uut/query1_en
add wave -noupdate /mac_vlan_rate_tb/uut/read_type
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/read_vtag
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/read_cmax
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/read_len
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/read_incr
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/read_count
add wave -noupdate /mac_vlan_rate_tb/uut/read_mode
add wave -noupdate /mac_vlan_rate_tb/uut/read_scale
add wave -noupdate /mac_vlan_rate_tb/uut/pre_type
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/pre_vtag
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/pre_decr
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/pre_cmax
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/pre_cmin
add wave -noupdate /mac_vlan_rate_tb/uut/pre_mode
add wave -noupdate /mac_vlan_rate_tb/uut/pre_index
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/pre_count
add wave -noupdate /mac_vlan_rate_tb/uut/mod_mode
add wave -noupdate /mac_vlan_rate_tb/uut/mod_type
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/mod_vtag
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/mod_addr
add wave -noupdate /mac_vlan_rate_tb/uut/mod_dei
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/mod_count
add wave -noupdate /mac_vlan_rate_tb/uut/mod_write
add wave -noupdate -radix hexadecimal /mac_vlan_rate_tb/uut/fin_count
add wave -noupdate /mac_vlan_rate_tb/uut/fin_keep
add wave -noupdate /mac_vlan_rate_tb/uut/fin_himask
add wave -noupdate /mac_vlan_rate_tb/uut/fin_write
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {141990 ns} 0}
configure wave -namecolwidth 280
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
WaveRestoreZoom {141907 ns} {142195 ns}
