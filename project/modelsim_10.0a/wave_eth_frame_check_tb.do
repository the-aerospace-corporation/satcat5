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
add wave -noupdate -divider {Input and output streams}
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/in_data
add wave -noupdate /eth_frame_check_tb/in_last
add wave -noupdate /eth_frame_check_tb/in_write
add wave -noupdate /eth_frame_check_tb/in_commit
add wave -noupdate /eth_frame_check_tb/in_revert
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/out_data
add wave -noupdate /eth_frame_check_tb/out_write
add wave -noupdate /eth_frame_check_tb/out_commit
add wave -noupdate /eth_frame_check_tb/out_revert
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/ref_data
add wave -noupdate /eth_frame_check_tb/ref_commit
add wave -noupdate /eth_frame_check_tb/ref_revert
add wave -noupdate -divider {Source parameters}
add wave -noupdate /eth_frame_check_tb/p_src/pkt_rem
add wave -noupdate /eth_frame_check_tb/u_src/pkt_len
add wave -noupdate /eth_frame_check_tb/u_src/p_src/pkt_usr
add wave -noupdate /eth_frame_check_tb/p_src/pkt_valid
add wave -noupdate /eth_frame_check_tb/p_src/pkt_badfcs
add wave -noupdate /eth_frame_check_tb/p_src/pkt_badlen
add wave -noupdate -divider {UUT Internals}
add wave -noupdate /eth_frame_check_tb/uut/reg_write
add wave -noupdate /eth_frame_check_tb/uut/reg_last
add wave -noupdate /eth_frame_check_tb/uut/byte_first
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut/crc_sreg
add wave -noupdate -radix unsigned /eth_frame_check_tb/uut/len_count
add wave -noupdate -radix unsigned /eth_frame_check_tb/uut/len_field
add wave -noupdate /eth_frame_check_tb/uut/frame_ok
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1098385000 ps} 0}
configure wave -namecolwidth 291
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
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {2100 us}
