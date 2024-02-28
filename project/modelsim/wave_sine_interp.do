# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {UUT0}
add wave -noupdate -color Red -format Analog-Step -height 40 -max 8192.0 /sine_interp_tb/uut0/ref_cos
add wave -noupdate -format Analog-Step -height 40 -min -8192.0 -radix decimal /sine_interp_tb/uut0/out_cos
add wave -noupdate -color Red -format Analog-Step -height 40 -max 8192.0 /sine_interp_tb/uut0/ref_sin
add wave -noupdate -format Analog-Step -height 40 -min -8192.0 -radix decimal /sine_interp_tb/uut0/out_sin
add wave -noupdate -divider {UUT1}
add wave -noupdate -color Red -format Analog-Step -height 40 -max 16384.0 /sine_interp_tb/uut1/ref_cos
add wave -noupdate -format Analog-Step -height 40 -min -16384.0 -radix decimal /sine_interp_tb/uut1/out_cos
add wave -noupdate -color Red -format Analog-Step -height 40 -max 16384.0 /sine_interp_tb/uut1/ref_sin
add wave -noupdate -format Analog-Step -height 40 -min -16384.0 -16384 decimal /sine_interp_tb/uut1/out_sin
add wave -noupdate -divider {UUT2}
add wave -noupdate -color Red -format Analog-Step -height 40 -max 32768.0 /sine_interp_tb/uut2/ref_cos
add wave -noupdate -format Analog-Step -height 40 -min -32768.0 -radix decimal /sine_interp_tb/uut2/out_cos
add wave -noupdate -color Red -format Analog-Step -height 40 -max 32768.0 /sine_interp_tb/uut2/ref_sin
add wave -noupdate -format Analog-Step -height 40 -min -32768.0 -radix decimal /sine_interp_tb/uut2/out_sin
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {13455 ns} 0}
configure wave -namecolwidth 150
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
WaveRestoreZoom {0 ns} {115500 ns}
