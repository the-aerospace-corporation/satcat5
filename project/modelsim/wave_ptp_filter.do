# Copyright 2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -clampanalog 1 -format Analog-Step -height 80 -max 281475000000000.0 -radix unsigned /ptp_filter_tb/uut/in_tstamp
add wave -noupdate -clampanalog 1 -format Analog-Step -height 80 -max 281475000000000.0 -radix unsigned /ptp_filter_tb/uut/out_tstamp
add wave -noupdate -clampanalog 1 -format Analog-Step -height 80 -max 1000000.0 -min -1000000.0 -radix decimal /ptp_filter_tb/uut/filt_diff
add wave -noupdate -clampanalog 1 -format Analog-Step -height 80 -max 1000000.0 -min -1000000.0 -radix decimal /ptp_filter_tb/uut/filt_alpha
add wave -noupdate -clampanalog 1 -format Analog-Step -height 80 -max 1000000.0 -min -1000000.0 -radix decimal /ptp_filter_tb/uut/filt_beta
add wave -noupdate -clampanalog 1 -format Analog-Step -height 80 -max 140000000000.0 -min 130000000000.0 -radix unsigned /ptp_filter_tb/uut/filt_incr
add wave -noupdate -clampanalog 1 -format Analog-Step -height 80 -max 7.3786976294838206e+019 -radix unsigned /ptp_filter_tb/uut/filt_pha
add wave -noupdate -clampanalog 1 -format Analog-Step -height 80 -max 2251799813685248.0 -radix unsigned /ptp_filter_tb/uut/filt_tau
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1953212000 ps} 0}
configure wave -namecolwidth 292
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
WaveRestoreZoom {1182981450 ps} {3548944350 ps}
