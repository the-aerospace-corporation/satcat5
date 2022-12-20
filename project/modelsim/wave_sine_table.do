# Copyright 2022 The Aerospace Corporation
#
# This file is part of SatCat5.
#
# SatCat5 is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# SatCat5 is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {UUT0}
add wave -noupdate -color Red -format Analog-Step -height 40 -max 1024.0 /sine_table_tb/uut0/ref_cos
add wave -noupdate -format Analog-Step -height 40 -min -1024.0 -radix decimal /sine_table_tb/uut0/out_cos
add wave -noupdate -color Red -format Analog-Step -height 40 -max 1024.0 /sine_table_tb/uut0/ref_sin
add wave -noupdate -format Analog-Step -height 40 -min -1024.0 -radix decimal /sine_table_tb/uut0/out_sin
add wave -noupdate -color Red -format Analog-Step -height 40 -max 1024.0 /sine_table_tb/uut0/ref_saw
add wave -noupdate -format Analog-Step -height 40 -min -1024.0 -radix decimal /sine_table_tb/uut0/out_saw
add wave -noupdate -divider {UUT1}
add wave -noupdate -color Red -format Analog-Step -height 40 -max 512.0 /sine_table_tb/uut1/ref_cos
add wave -noupdate -format Analog-Step -height 40 -min -512.0 -radix decimal /sine_table_tb/uut1/out_cos
add wave -noupdate -color Red -format Analog-Step -height 40 -max 512.0 /sine_table_tb/uut1/ref_sin
add wave -noupdate -format Analog-Step -height 40 -min -512.0 -radix decimal /sine_table_tb/uut1/out_sin
add wave -noupdate -color Red -format Analog-Step -height 40 -max 512.0 /sine_table_tb/uut1/ref_saw
add wave -noupdate -format Analog-Step -height 40 -min -512.0 -radix decimal /sine_table_tb/uut1/out_saw
add wave -noupdate -divider {UUT2}
add wave -noupdate -color Red -format Analog-Step -height 40 -max 2048.0 /sine_table_tb/uut2/ref_cos
add wave -noupdate -format Analog-Step -height 40 -min -2048.0 -radix decimal /sine_table_tb/uut2/out_cos
add wave -noupdate -color Red -format Analog-Step -height 40 -max 2048.0 /sine_table_tb/uut2/ref_sin
add wave -noupdate -format Analog-Step -height 40 -min -2048.0 -radix decimal /sine_table_tb/uut2/out_sin
add wave -noupdate -color Red -format Analog-Step -height 40 -max 2048.0 /sine_table_tb/uut2/ref_saw
add wave -noupdate -format Analog-Step -height 40 -min -2048.0 -radix decimal /sine_table_tb/uut2/out_saw
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
