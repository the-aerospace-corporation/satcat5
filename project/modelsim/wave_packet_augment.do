# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider Test0
add wave -noupdate -radix hexadecimal /packet_augment_tb/test0/in_data
add wave -noupdate /packet_augment_tb/test0/in_nlast
add wave -noupdate /packet_augment_tb/test0/in_valid
add wave -noupdate /packet_augment_tb/test0/in_ready
add wave -noupdate /packet_augment_tb/test0/in_wcount
add wave -noupdate -radix hexadecimal /packet_augment_tb/test0/ref_data
add wave -noupdate -radix hexadecimal /packet_augment_tb/test0/ref_mask
add wave -noupdate /packet_augment_tb/test0/ref_nlast
add wave -noupdate -radix hexadecimal /packet_augment_tb/test0/out_data
add wave -noupdate /packet_augment_tb/test0/out_nlast
add wave -noupdate /packet_augment_tb/test0/out_valid
add wave -noupdate /packet_augment_tb/test0/out_ready
add wave -noupdate /packet_augment_tb/test0/out_wcount
add wave -noupdate -divider Test1
add wave -noupdate -radix hexadecimal /packet_augment_tb/test1/in_data
add wave -noupdate /packet_augment_tb/test1/in_nlast
add wave -noupdate /packet_augment_tb/test1/in_valid
add wave -noupdate /packet_augment_tb/test1/in_ready
add wave -noupdate /packet_augment_tb/test1/in_wcount
add wave -noupdate -radix hexadecimal /packet_augment_tb/test1/ref_data
add wave -noupdate -radix hexadecimal /packet_augment_tb/test1/ref_mask
add wave -noupdate /packet_augment_tb/test1/ref_nlast
add wave -noupdate -radix hexadecimal /packet_augment_tb/test1/out_data
add wave -noupdate /packet_augment_tb/test1/out_nlast
add wave -noupdate /packet_augment_tb/test1/out_valid
add wave -noupdate /packet_augment_tb/test1/out_ready
add wave -noupdate /packet_augment_tb/test1/out_wcount
add wave -noupdate -divider Test2
add wave -noupdate -radix hexadecimal /packet_augment_tb/test2/in_data
add wave -noupdate /packet_augment_tb/test2/in_nlast
add wave -noupdate /packet_augment_tb/test2/in_valid
add wave -noupdate /packet_augment_tb/test2/in_ready
add wave -noupdate /packet_augment_tb/test2/in_wcount
add wave -noupdate -radix hexadecimal /packet_augment_tb/test2/ref_data
add wave -noupdate -radix hexadecimal /packet_augment_tb/test2/ref_mask
add wave -noupdate /packet_augment_tb/test2/ref_nlast
add wave -noupdate -radix hexadecimal /packet_augment_tb/test2/out_data
add wave -noupdate /packet_augment_tb/test2/out_nlast
add wave -noupdate /packet_augment_tb/test2/out_valid
add wave -noupdate /packet_augment_tb/test2/out_ready
add wave -noupdate /packet_augment_tb/test2/out_wcount
add wave -noupdate -divider Test3
add wave -noupdate -radix hexadecimal /packet_augment_tb/test3/in_data
add wave -noupdate /packet_augment_tb/test3/in_nlast
add wave -noupdate /packet_augment_tb/test3/in_valid
add wave -noupdate /packet_augment_tb/test3/in_ready
add wave -noupdate /packet_augment_tb/test3/in_wcount
add wave -noupdate -radix hexadecimal /packet_augment_tb/test3/ref_data
add wave -noupdate -radix hexadecimal /packet_augment_tb/test3/ref_mask
add wave -noupdate /packet_augment_tb/test3/ref_nlast
add wave -noupdate -radix hexadecimal /packet_augment_tb/test3/out_data
add wave -noupdate /packet_augment_tb/test3/out_nlast
add wave -noupdate /packet_augment_tb/test3/out_valid
add wave -noupdate /packet_augment_tb/test3/out_ready
add wave -noupdate /packet_augment_tb/test3/out_wcount
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {9999237 ps} 0}
configure wave -namecolwidth 230
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
WaveRestoreZoom {9999050 ps} {9999952 ps}
