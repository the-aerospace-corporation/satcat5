# Copyright 2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /config_timestamp_tb/ctr_ref
add wave -noupdate -radix hexadecimal /config_timestamp_tb/ctr_out0
add wave -noupdate -radix hexadecimal /config_timestamp_tb/ctr_out1
add wave -noupdate -radix hexadecimal /config_timestamp_tb/ctr_out2
add wave -noupdate /config_timestamp_tb/uut0/count_div
add wave -noupdate /config_timestamp_tb/uut0/count_en
add wave -noupdate /config_timestamp_tb/uut1/count_div
add wave -noupdate /config_timestamp_tb/uut1/count_en
add wave -noupdate /config_timestamp_tb/uut2/count_div
add wave -noupdate /config_timestamp_tb/uut2/count_en
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {692277 ps} 0}
configure wave -namecolwidth 251
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
WaveRestoreZoom {388316 ps} {3663773 ps}
