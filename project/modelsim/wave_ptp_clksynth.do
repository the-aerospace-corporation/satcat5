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
