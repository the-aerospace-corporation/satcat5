# Copyright 2019 The Aerospace Corporation
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
add wave -noupdate -divider {Test control}
add wave -noupdate /sgmii_data_slip_tb/test_index
add wave -noupdate /sgmii_data_slip_tb/test_offset
add wave -noupdate /sgmii_data_slip_tb/test_rate
add wave -noupdate -divider {Input and Output Streams}
add wave -noupdate -radix hexadecimal /sgmii_data_slip_tb/in_data
add wave -noupdate /sgmii_data_slip_tb/in_next
add wave -noupdate -radix hexadecimal /sgmii_data_slip_tb/ref_data
add wave -noupdate -radix hexadecimal /sgmii_data_slip_tb/out_data
add wave -noupdate /sgmii_data_slip_tb/out_next
add wave -noupdate -divider {Slip commands}
add wave -noupdate /sgmii_data_slip_tb/slip_early
add wave -noupdate /sgmii_data_slip_tb/slip_late
add wave -noupdate /sgmii_data_slip_tb/slip_ready
add wave -noupdate -divider {UUT Internals}
add wave -noupdate -radix hexadecimal /sgmii_data_slip_tb/uut/sreg_data
add wave -noupdate /sgmii_data_slip_tb/uut/sreg_idx
add wave -noupdate /sgmii_data_slip_tb/uut/flag_add
add wave -noupdate /sgmii_data_slip_tb/uut/flag_drop
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {7857581688 ps} 0}
configure wave -namecolwidth 340
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
WaveRestoreZoom {0 ps} {17577 us}
