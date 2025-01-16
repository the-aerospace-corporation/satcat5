# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/ref_rtc
add wave -noupdate /ptp_pps_tb/uut0/ref_pps
add wave -noupdate /ptp_pps_tb/uut0/uut_pps
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/cfg_cmd
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/cfg_ack
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/test_phase
add wave -noupdate /ptp_pps_tb/uut0/test_rising
add wave -noupdate /ptp_pps_tb/uut0/test_check
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/uut_out/par_rtc
add wave -noupdate /ptp_pps_tb/uut0/uut_out/par_shdn
add wave -noupdate /ptp_pps_tb/uut0/uut_out/par_pps_out
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/uut_out/mod_tstamp
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/uut_out/mod_dither
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/uut_out/mod_offset
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/uut_out/mod_final
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/uut_out/cpu_offset
add wave -noupdate /ptp_pps_tb/uut0/uut_out/cpu_rising
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/uut_in/par_rtc
add wave -noupdate /ptp_pps_tb/uut0/uut_in/par_rtc_ok
add wave -noupdate /ptp_pps_tb/uut0/uut_in/par_pps_in
add wave -noupdate /ptp_pps_tb/uut0/uut_in/par_early
add wave -noupdate /ptp_pps_tb/uut0/uut_in/par_late
add wave -noupdate /ptp_pps_tb/uut0/uut_in/par_prev
add wave -noupdate /ptp_pps_tb/uut0/uut_in/edge_vec
add wave -noupdate /ptp_pps_tb/uut0/uut_in/edge_det
add wave -noupdate /ptp_pps_tb/uut0/uut_in/edge_idx
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/uut_in/adj_sec
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/uut_in/adj_subns
add wave -noupdate /ptp_pps_tb/uut0/uut_in/adj_write
add wave -noupdate /ptp_pps_tb/uut0/uut_in/fifo_count
add wave -noupdate -radix hexadecimal /ptp_pps_tb/uut0/uut_in/fifo_sreg
add wave -noupdate /ptp_pps_tb/uut0/uut_in/fifo_last
add wave -noupdate /ptp_pps_tb/uut0/uut_in/fifo_valid
add wave -noupdate /ptp_pps_tb/uut0/uut_in/fifo_ready
add wave -noupdate /ptp_pps_tb/uut0/uut_in/cpu_clear
add wave -noupdate /ptp_pps_tb/uut0/uut_in/cpu_rising
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {446 ps} 0}
configure wave -namecolwidth 266
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
WaveRestoreZoom {0 ps} {879 ps}
