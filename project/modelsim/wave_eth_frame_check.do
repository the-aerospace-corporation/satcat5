# Copyright 2021-2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider UUT1a
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/in_data
add wave -noupdate /eth_frame_check_tb/uut1a/in_nlast
add wave -noupdate /eth_frame_check_tb/uut1a/in_write
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/ref_data
add wave -noupdate /eth_frame_check_tb/uut1a/ref_nlast
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/ref_result
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/out_data
add wave -noupdate /eth_frame_check_tb/uut1a/out_nlast
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1a/out_result
add wave -noupdate /eth_frame_check_tb/uut1a/out_write
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
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1b/ref_result
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1b/out_data
add wave -noupdate /eth_frame_check_tb/uut1b/out_nlast
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut1b/out_result
add wave -noupdate /eth_frame_check_tb/uut1b/out_write
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
add wave -noupdate -divider UUT2a
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2a/in_data
add wave -noupdate /eth_frame_check_tb/uut2a/in_nlast
add wave -noupdate /eth_frame_check_tb/uut2a/in_write
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2a/ref_data
add wave -noupdate /eth_frame_check_tb/uut2a/ref_nlast
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2a/ref_result
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2a/out_data
add wave -noupdate /eth_frame_check_tb/uut2a/out_nlast
add wave -noupdate /eth_frame_check_tb/uut2a/out_write
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2a/out_result
add wave -noupdate -divider UUT2b
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2b/in_data
add wave -noupdate /eth_frame_check_tb/uut2b/in_nlast
add wave -noupdate /eth_frame_check_tb/uut2b/in_write
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2b/ref_data
add wave -noupdate /eth_frame_check_tb/uut2b/ref_nlast
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2b/ref_result
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2b/out_data
add wave -noupdate /eth_frame_check_tb/uut2b/out_nlast
add wave -noupdate /eth_frame_check_tb/uut2b/out_write
add wave -noupdate -radix hexadecimal /eth_frame_check_tb/uut2b/out_result
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {99481055 ps} 0}
configure wave -namecolwidth 273
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
WaveRestoreZoom {99376561 ps} {100014606 ps}
