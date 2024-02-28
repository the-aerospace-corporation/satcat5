# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider UUT0
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut0/ref_incr
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut0/par_out
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut0/par_ref
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut0/par_tstamp
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut0/uut/mod_offset
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut0/uut/mod_time
add wave -noupdate -divider UUT1
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut1/ref_incr
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut1/par_out
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut1/par_ref
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut1/par_tstamp
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut1/uut/mod_offset
add wave -noupdate -radix hexadecimal /ptp_clksynth_tb/uut1/uut/mod_time
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {9043181 ps} 0}
configure wave -namecolwidth 236
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
WaveRestoreZoom {8753114 ps} {10065626 ps}
