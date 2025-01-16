# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix unsigned /router2_qdepth_tb/uut0/test_qdepth
add wave -noupdate -format Analog-Step -height 74 -max 254.99999999999997 -radix unsigned /router2_qdepth_tb/uut0/out_qdepth
add wave -noupdate -radix unsigned /router2_qdepth_tb/uut1/test_qdepth
add wave -noupdate -format Analog-Step -height 74 -max 254.0 -radix unsigned /router2_qdepth_tb/uut1/out_qdepth
add wave -noupdate -radix unsigned /router2_qdepth_tb/uut2/test_qdepth
add wave -noupdate -format Analog-Step -height 74 -max 254.0 -radix unsigned /router2_qdepth_tb/uut2/out_qdepth
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {2392597968 ps} 0}
configure wave -namecolwidth 289
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
WaveRestoreZoom {0 ps} {5250 us}
