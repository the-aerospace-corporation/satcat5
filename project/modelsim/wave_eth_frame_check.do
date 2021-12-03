# Copyright 2021 The Aerospace Corporation
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
add wave -noupdate -divider UUT1a
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/in_data
add wave -noupdate /eth_frame_check_tb/uut1a/in_nlast
add wave -noupdate /eth_frame_check_tb/uut1a/in_write
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/ref_data
add wave -noupdate /eth_frame_check_tb/uut1a/ref_nlast
add wave -noupdate /eth_frame_check_tb/uut1a/ref_commit
add wave -noupdate /eth_frame_check_tb/uut1a/ref_revert
add wave -noupdate /eth_frame_check_tb/uut1a/ref_error
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/out_data
add wave -noupdate /eth_frame_check_tb/uut1a/out_nlast
add wave -noupdate /eth_frame_check_tb/uut1a/out_write
add wave -noupdate /eth_frame_check_tb/uut1a/out_commit
add wave -noupdate /eth_frame_check_tb/uut1a/out_revert
add wave -noupdate /eth_frame_check_tb/uut1a/out_error
add wave -noupdate /eth_frame_check_tb/uut1a/ref_index
add wave -noupdate -divider {UUT1a internals}
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/uut/crc_result
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/uut/crc_data
add wave -noupdate /eth_frame_check_tb/uut1a/uut/crc_nlast
add wave -noupdate /eth_frame_check_tb/uut1a/uut/crc_write
add wave -noupdate /eth_frame_check_tb/uut1a/uut/chk_mctrl
add wave -noupdate /eth_frame_check_tb/uut1a/uut/chk_badsrc
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/uut/chk_etype
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/uut/chk_count
add wave -noupdate /eth_frame_check_tb/uut1a/uut/frm_ok
add wave -noupdate /eth_frame_check_tb/uut1a/uut/frm_keep
add wave -noupdate -divider UUT1b
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1b/in_data
add wave -noupdate /eth_frame_check_tb/uut1b/in_nlast
add wave -noupdate /eth_frame_check_tb/uut1b/in_write
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1b/ref_data
add wave -noupdate /eth_frame_check_tb/uut1b/ref_nlast
add wave -noupdate /eth_frame_check_tb/uut1b/ref_commit
add wave -noupdate /eth_frame_check_tb/uut1b/ref_revert
add wave -noupdate /eth_frame_check_tb/uut1b/ref_error
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1b/out_data
add wave -noupdate /eth_frame_check_tb/uut1b/out_nlast
add wave -noupdate /eth_frame_check_tb/uut1b/out_write
add wave -noupdate /eth_frame_check_tb/uut1b/out_commit
add wave -noupdate /eth_frame_check_tb/uut1b/out_revert
add wave -noupdate /eth_frame_check_tb/uut1b/out_error
add wave -noupdate -divider {UUT1b internals}
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1b/uut/crc_result
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1b/uut/crc_data
add wave -noupdate /eth_frame_check_tb/uut1b/uut/crc_nlast
add wave -noupdate /eth_frame_check_tb/uut1b/uut/crc_write
add wave -noupdate /eth_frame_check_tb/uut1b/uut/chk_mctrl
add wave -noupdate /eth_frame_check_tb/uut1b/uut/chk_badsrc
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1b/uut/chk_etype
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1b/uut/chk_count
add wave -noupdate /eth_frame_check_tb/uut1b/uut/frm_ok
add wave -noupdate /eth_frame_check_tb/uut1b/uut/frm_keep
add wave -noupdate /eth_frame_check_tb/uut1b/uut/gen_strip/p_strip/DELAY_MAX
add wave -noupdate /eth_frame_check_tb/uut1b/uut/gen_strip/p_strip/sreg
add wave -noupdate /eth_frame_check_tb/uut1b/uut/gen_strip/p_strip/OVR_THR
add wave -noupdate /eth_frame_check_tb/uut1b/uut/gen_strip/p_strip/ovr_ct
add wave -noupdate /eth_frame_check_tb/uut1b/uut/gen_strip/p_strip/count
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {99480789 ps} 0}
configure wave -namecolwidth 250
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
WaveRestoreZoom {99376561 ps} {100032813 ps}
