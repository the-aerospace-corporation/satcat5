# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {UUT0 Stimulus}
add wave -noupdate /ptp_egress_tb/uut0/test_index
add wave -noupdate /ptp_egress_tb/uut0/test_2step
add wave -noupdate -radix hexadecimal /ptp_egress_tb/uut0/test_meta_i
add wave -noupdate -radix hexadecimal /ptp_egress_tb/uut0/test_meta_p
add wave -noupdate -radix hexadecimal /ptp_egress_tb/uut0/in_meta
add wave -noupdate -radix hexadecimal /ptp_egress_tb/uut0/in_data
add wave -noupdate /ptp_egress_tb/uut0/in_nlast
add wave -noupdate /ptp_egress_tb/uut0/in_valid
add wave -noupdate /ptp_egress_tb/uut0/in_ready
add wave -noupdate -radix hexadecimal /ptp_egress_tb/uut0/out_data
add wave -noupdate /ptp_egress_tb/uut0/out_error
add wave -noupdate /ptp_egress_tb/uut0/out_nlast
add wave -noupdate /ptp_egress_tb/uut0/out_valid
add wave -noupdate /ptp_egress_tb/uut0/out_ready
add wave -noupdate -radix hexadecimal /ptp_egress_tb/uut0/ref_meta
add wave -noupdate -radix hexadecimal /ptp_egress_tb/uut0/ref_data
add wave -noupdate /ptp_egress_tb/uut0/ref_nlast
add wave -noupdate /ptp_egress_tb/uut0/ref_valid
add wave -noupdate /ptp_egress_tb/uut0/ref_ready
add wave -noupdate -divider {UUT0 Internals}
add wave -noupdate /ptp_egress_tb/uut0/uut/in_wcount
add wave -noupdate /ptp_egress_tb/uut0/uut/in_adj_time
add wave -noupdate /ptp_egress_tb/uut0/uut/in_adj_freq
add wave -noupdate -radix hexadecimal /ptp_egress_tb/uut0/uut/tcorr_time
add wave -noupdate -radix hexadecimal /ptp_egress_tb/uut0/uut/tcorr_freq
add wave -noupdate /ptp_egress_tb/uut0/uut/tcorr_rd
add wave -noupdate /ptp_egress_tb/uut0/uut/tcorr_error
add wave -noupdate -radix hexadecimal /ptp_egress_tb/uut0/uut/mod_data
add wave -noupdate /ptp_egress_tb/uut0/uut/mod_nlast
add wave -noupdate /ptp_egress_tb/uut0/uut/mod_valid
add wave -noupdate /ptp_egress_tb/uut0/uut/mod_ready
add wave -noupdate /ptp_egress_tb/uut0/uut/mod_2step
add wave -noupdate /ptp_egress_tb/uut0/uut/mod_pstart
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {148965000 ps} 0}
configure wave -namecolwidth 224
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
WaveRestoreZoom {148964540 ps} {148965460 ps}
