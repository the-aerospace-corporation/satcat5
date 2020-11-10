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

add wave -noupdate -divider {UUT0}
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut0/in_data
add wave -noupdate /eth_frame_check_tb/uut0/in_last
add wave -noupdate /eth_frame_check_tb/uut0/in_write
add wave -noupdate /eth_frame_check_tb/uut0/mod_write
add wave -noupdate /eth_frame_check_tb/uut0/mod_commit
add wave -noupdate /eth_frame_check_tb/uut0/mod_revert
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut0/out_data
add wave -noupdate /eth_frame_check_tb/uut0/out_write
add wave -noupdate /eth_frame_check_tb/uut0/out_commit
add wave -noupdate /eth_frame_check_tb/uut0/out_revert
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut0/ref_data
add wave -noupdate /eth_frame_check_tb/uut0/ref_commit
add wave -noupdate /eth_frame_check_tb/uut0/ref_revert
add wave -noupdate /eth_frame_check_tb/uut0/p_src/pkt_rem
add wave -noupdate /eth_frame_check_tb/uut0/u_src/pkt_len
add wave -noupdate /eth_frame_check_tb/uut0/u_src/p_src/pkt_usr
add wave -noupdate /eth_frame_check_tb/uut0/p_src/pkt_valid
add wave -noupdate /eth_frame_check_tb/uut0/p_src/pkt_badfcs
add wave -noupdate /eth_frame_check_tb/uut0/p_src/pkt_badlen

add wave -noupdate -divider {UUT1}
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1/in_data
add wave -noupdate /eth_frame_check_tb/uut1/in_last
add wave -noupdate /eth_frame_check_tb/uut1/in_write
add wave -noupdate /eth_frame_check_tb/uut1/mod_write
add wave -noupdate /eth_frame_check_tb/uut1/mod_commit
add wave -noupdate /eth_frame_check_tb/uut1/mod_revert
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1/out_data
add wave -noupdate /eth_frame_check_tb/uut1/out_write
add wave -noupdate /eth_frame_check_tb/uut1/out_commit
add wave -noupdate /eth_frame_check_tb/uut1/out_revert
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1/ref_data
add wave -noupdate /eth_frame_check_tb/uut1/ref_commit
add wave -noupdate /eth_frame_check_tb/uut1/ref_revert
add wave -noupdate /eth_frame_check_tb/uut1/p_src/pkt_rem
add wave -noupdate /eth_frame_check_tb/uut1/u_src/pkt_len
add wave -noupdate /eth_frame_check_tb/uut1/u_src/p_src/pkt_usr
add wave -noupdate /eth_frame_check_tb/uut1/p_src/pkt_valid
add wave -noupdate /eth_frame_check_tb/uut1/p_src/pkt_badfcs
add wave -noupdate /eth_frame_check_tb/uut1/p_src/pkt_badlen

add wave -noupdate -divider {UUT2}
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2/in_data
add wave -noupdate /eth_frame_check_tb/uut2/in_last
add wave -noupdate /eth_frame_check_tb/uut2/in_write
add wave -noupdate /eth_frame_check_tb/uut2/mod_write
add wave -noupdate /eth_frame_check_tb/uut2/mod_commit
add wave -noupdate /eth_frame_check_tb/uut2/mod_revert
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2/out_data
add wave -noupdate /eth_frame_check_tb/uut2/out_write
add wave -noupdate /eth_frame_check_tb/uut2/out_commit
add wave -noupdate /eth_frame_check_tb/uut2/out_revert
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2/ref_data
add wave -noupdate /eth_frame_check_tb/uut2/ref_commit
add wave -noupdate /eth_frame_check_tb/uut2/ref_revert
add wave -noupdate /eth_frame_check_tb/uut2/p_src/pkt_rem
add wave -noupdate /eth_frame_check_tb/uut2/u_src/pkt_len
add wave -noupdate /eth_frame_check_tb/uut2/u_src/p_src/pkt_usr
add wave -noupdate /eth_frame_check_tb/uut2/p_src/pkt_valid
add wave -noupdate /eth_frame_check_tb/uut2/p_src/pkt_badfcs
add wave -noupdate /eth_frame_check_tb/uut2/p_src/pkt_badlen

add wave -noupdate -divider {UUT3}
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut3/in_data
add wave -noupdate /eth_frame_check_tb/uut3/in_last
add wave -noupdate /eth_frame_check_tb/uut3/in_write
add wave -noupdate /eth_frame_check_tb/uut3/mod_write
add wave -noupdate /eth_frame_check_tb/uut3/mod_commit
add wave -noupdate /eth_frame_check_tb/uut3/mod_revert
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut3/out_data
add wave -noupdate /eth_frame_check_tb/uut3/out_write
add wave -noupdate /eth_frame_check_tb/uut3/out_commit
add wave -noupdate /eth_frame_check_tb/uut3/out_revert
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut3/ref_data
add wave -noupdate /eth_frame_check_tb/uut3/ref_commit
add wave -noupdate /eth_frame_check_tb/uut3/ref_revert
add wave -noupdate /eth_frame_check_tb/uut3/p_src/pkt_rem
add wave -noupdate /eth_frame_check_tb/uut3/u_src/pkt_len
add wave -noupdate /eth_frame_check_tb/uut3/u_src/p_src/pkt_usr
add wave -noupdate /eth_frame_check_tb/uut3/p_src/pkt_valid
add wave -noupdate /eth_frame_check_tb/uut3/p_src/pkt_badfcs
add wave -noupdate /eth_frame_check_tb/uut3/p_src/pkt_badlen

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
