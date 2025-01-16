# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider UUT0
add wave -noupdate /router2_ipchksum_tb/uut0/test_index
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut0/in_data
add wave -noupdate /router2_ipchksum_tb/uut0/in_nlast
add wave -noupdate /router2_ipchksum_tb/uut0/in_write
add wave -noupdate /router2_ipchksum_tb/uut0/in_meta
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut0/out_data
add wave -noupdate /router2_ipchksum_tb/uut0/out_nlast
add wave -noupdate /router2_ipchksum_tb/uut0/out_write
add wave -noupdate /router2_ipchksum_tb/uut0/out_meta
add wave -noupdate /router2_ipchksum_tb/uut0/out_match
add wave -noupdate /router2_ipchksum_tb/uut0/out_error
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut0/ref_data
add wave -noupdate /router2_ipchksum_tb/uut0/ref_nlast
add wave -noupdate /router2_ipchksum_tb/uut0/ref_valid
add wave -noupdate /router2_ipchksum_tb/uut0/ref_meta
add wave -noupdate -divider UUT1
add wave -noupdate /router2_ipchksum_tb/uut1/test_index
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut1/in_data
add wave -noupdate /router2_ipchksum_tb/uut1/in_nlast
add wave -noupdate /router2_ipchksum_tb/uut1/in_write
add wave -noupdate /router2_ipchksum_tb/uut1/in_meta
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut1/out_data
add wave -noupdate /router2_ipchksum_tb/uut1/out_nlast
add wave -noupdate /router2_ipchksum_tb/uut1/out_write
add wave -noupdate /router2_ipchksum_tb/uut1/out_meta
add wave -noupdate /router2_ipchksum_tb/uut1/out_match
add wave -noupdate /router2_ipchksum_tb/uut1/out_error
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut1/ref_data
add wave -noupdate /router2_ipchksum_tb/uut1/ref_nlast
add wave -noupdate /router2_ipchksum_tb/uut1/ref_valid
add wave -noupdate /router2_ipchksum_tb/uut1/ref_meta
add wave -noupdate -divider UUT2
add wave -noupdate /router2_ipchksum_tb/uut2/test_index
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut2/in_data
add wave -noupdate /router2_ipchksum_tb/uut2/in_nlast
add wave -noupdate /router2_ipchksum_tb/uut2/in_write
add wave -noupdate /router2_ipchksum_tb/uut2/in_meta
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut2/out_data
add wave -noupdate /router2_ipchksum_tb/uut2/out_nlast
add wave -noupdate /router2_ipchksum_tb/uut2/out_write
add wave -noupdate /router2_ipchksum_tb/uut2/out_meta
add wave -noupdate /router2_ipchksum_tb/uut2/out_match
add wave -noupdate /router2_ipchksum_tb/uut2/out_error
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut2/ref_data
add wave -noupdate /router2_ipchksum_tb/uut2/ref_nlast
add wave -noupdate /router2_ipchksum_tb/uut2/ref_valid
add wave -noupdate /router2_ipchksum_tb/uut2/ref_meta
add wave -noupdate -divider UUT3
add wave -noupdate /router2_ipchksum_tb/uut3/test_index
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut3/in_data
add wave -noupdate /router2_ipchksum_tb/uut3/in_nlast
add wave -noupdate /router2_ipchksum_tb/uut3/in_write
add wave -noupdate /router2_ipchksum_tb/uut3/in_meta
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut3/out_data
add wave -noupdate /router2_ipchksum_tb/uut3/out_nlast
add wave -noupdate /router2_ipchksum_tb/uut3/out_write
add wave -noupdate /router2_ipchksum_tb/uut3/out_meta
add wave -noupdate /router2_ipchksum_tb/uut3/out_match
add wave -noupdate /router2_ipchksum_tb/uut3/out_error
add wave -noupdate -radix hexadecimal /router2_ipchksum_tb/uut3/ref_data
add wave -noupdate /router2_ipchksum_tb/uut3/ref_nlast
add wave -noupdate /router2_ipchksum_tb/uut3/ref_valid
add wave -noupdate /router2_ipchksum_tb/uut3/ref_meta
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {176 ps} 0}
configure wave -namecolwidth 256
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
WaveRestoreZoom {0 ps} {846 ps}