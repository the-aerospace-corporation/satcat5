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
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/in_psrc
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/in_data
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/in_last
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/in_valid
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/in_ready
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/out_pdst
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/out_valid
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/out_ready
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/error_full
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/error_table
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/p_mac_sreg/count
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/mac_addr
add wave -noupdate -radix unsigned /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/mac_psrc
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/mac_rdy_dst
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/mac_rdy_src
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/cam_match
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/cam_rdy_dst
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/cam_rdy_src
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/cam_macaddr
add wave -noupdate -radix unsigned /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/cam_psrc
add wave -noupdate -radix unsigned /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/cam_tidx
add wave -noupdate -radix unsigned /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/tbl_pidx
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/pdst_mask
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/pdst_rdy
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/fifo_ready
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/init_count
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/init_done
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/camwr_mask
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/camwr_mac
add wave -noupdate -radix unsigned /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/camwr_tidx
add wave -noupdate -radix unsigned /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/camwr_psrc
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/camwr_twr
add wave -noupdate /mac_lookup_tb/u_lutram/uut/gen_lutram/u_mac/camwr_full
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1955 ns} 0}
configure wave -namecolwidth 390
configure wave -valuecolwidth 125
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
WaveRestoreZoom {1542 ns} {1986 ns}
