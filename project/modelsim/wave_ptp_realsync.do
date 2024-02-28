# Copyright 2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test Control}
add wave -noupdate -radix hexadecimal /ptp_realsync_tb/test_offset
add wave -noupdate /ptp_realsync_tb/test_reset
add wave -noupdate -radix hexadecimal /ptp_realsync_tb/ref_tstamp
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/ptp_realsync_tb/ref_rtc.sec {-height 15 -radix hexadecimal} /ptp_realsync_tb/ref_rtc.nsec {-height 15 -radix hexadecimal} /ptp_realsync_tb/ref_rtc.subns {-height 15 -radix hexadecimal}} /ptp_realsync_tb/ref_rtc
add wave -noupdate -radix hexadecimal /ptp_realsync_tb/out_tstamp
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/ptp_realsync_tb/out_rtc_ref.sec {-height 15 -radix hexadecimal} /ptp_realsync_tb/out_rtc_ref.nsec {-height 15 -radix hexadecimal} /ptp_realsync_tb/out_rtc_ref.subns {-height 15 -radix hexadecimal}} /ptp_realsync_tb/out_rtc_ref
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/ptp_realsync_tb/out_rtc_uut.sec {-height 15 -radix hexadecimal} /ptp_realsync_tb/out_rtc_uut.nsec {-height 15 -radix hexadecimal} /ptp_realsync_tb/out_rtc_uut.subns {-height 15 -radix hexadecimal}} /ptp_realsync_tb/out_rtc_uut
add wave -noupdate -divider UUT
add wave -noupdate -radix hexadecimal /ptp_realsync_tb/uut/xout_tdiff
add wave -noupdate -radix hexadecimal /ptp_realsync_tb/uut/xout_sec
add wave -noupdate -radix hexadecimal /ptp_realsync_tb/uut/sum_tdiff
add wave -noupdate -radix hexadecimal /ptp_realsync_tb/uut/sum_sec
add wave -noupdate -radix hexadecimal /ptp_realsync_tb/uut/roll_subns
add wave -noupdate -radix hexadecimal /ptp_realsync_tb/uut/roll_sec
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {2009953 ns} 0}
configure wave -namecolwidth 226
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
WaveRestoreZoom {2009945 ns} {2010003 ns}
