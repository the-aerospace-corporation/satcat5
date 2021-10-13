# Copyright 2020 The Aerospace Corporation
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
add wave -noupdate -radix hexadecimal /config_port_test_tb/refctr_a2b0
add wave -noupdate -radix hexadecimal /config_port_test_tb/refctr_a2b1
add wave -noupdate -radix hexadecimal /config_port_test_tb/refctr_b2a0
add wave -noupdate -radix hexadecimal /config_port_test_tb/refctr_b2a1
add wave -noupdate -radix hexadecimal /config_port_test_tb/rx_report
add wave -noupdate -radix hexadecimal /config_port_test_tb/rx_byte
add wave -noupdate /config_port_test_tb/rx_write
add wave -noupdate -divider UUT
add wave -noupdate /config_port_test_tb/uut/rx_commit_r
add wave -noupdate /config_port_test_tb/uut/rx_revert_r
add wave -noupdate -radix hexadecimal /config_port_test_tb/uut/rx_count0
add wave -noupdate -radix hexadecimal /config_port_test_tb/uut/rx_count1
add wave -noupdate /config_port_test_tb/uut/report_start
add wave -noupdate /config_port_test_tb/uut/report_busy
add wave -noupdate /config_port_test_tb/uut/report_next
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {2005696 ns} 0}
configure wave -namecolwidth 264
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
WaveRestoreZoom {1874650 ns} {2025498 ns}
