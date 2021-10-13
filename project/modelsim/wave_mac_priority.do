# Copyright 2021 The Aerospace Corporation
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
add wave -noupdate /mac_priority_tb/reset_p
add wave -noupdate -radix hexadecimal /mac_priority_tb/in_data
add wave -noupdate /mac_priority_tb/in_last
add wave -noupdate /mac_priority_tb/in_write
add wave -noupdate /mac_priority_tb/out_pri
add wave -noupdate /mac_priority_tb/out_valid
add wave -noupdate /mac_priority_tb/out_ready
add wave -noupdate /mac_priority_tb/out_count
add wave -noupdate /mac_priority_tb/ref_pri
add wave -noupdate /mac_priority_tb/ref_valid
add wave -noupdate /mac_priority_tb/test_index
add wave -noupdate /mac_priority_tb/test_rate
add wave -noupdate /mac_priority_tb/test_sof
add wave -noupdate /mac_priority_tb/test_idle
add wave -noupdate /mac_priority_tb/test_pri
add wave -noupdate -radix hexadecimal /mac_priority_tb/test_etype
add wave -noupdate -radix hexadecimal /mac_priority_tb/uut/cfg_etype
add wave -noupdate /mac_priority_tb/uut/cfg_valid
add wave -noupdate /mac_priority_tb/uut/cfg_ready
add wave -noupdate /mac_priority_tb/uut/wcount
add wave -noupdate -radix hexadecimal /mac_priority_tb/uut/pkt_etype
add wave -noupdate /mac_priority_tb/uut/pkt_rdy
add wave -noupdate /mac_priority_tb/uut/tbl_found
add wave -noupdate /mac_priority_tb/uut/tbl_rdy
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {9624 ns} 0}
configure wave -namecolwidth 225
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
WaveRestoreZoom {9571 ns} {10023 ns}
