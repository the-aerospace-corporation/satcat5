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
add wave -noupdate /packet_inject_tb/test_idx
add wave -noupdate /packet_inject_tb/test_long
add wave -noupdate /packet_inject_tb/rate_pri
add wave -noupdate /packet_inject_tb/rate_aux
add wave -noupdate /packet_inject_tb/rate_out
add wave -noupdate /packet_inject_tb/in_errct
add wave -noupdate /packet_inject_tb/aux_errct
add wave -noupdate -divider {Input streams}
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/packet_inject_tb/in_data(2) {-height 15 -radix hexadecimal} /packet_inject_tb/in_data(1) {-height 15 -radix hexadecimal} /packet_inject_tb/in_data(0) {-height 15 -radix hexadecimal}} /packet_inject_tb/in_data
add wave -noupdate -expand /packet_inject_tb/in_last
add wave -noupdate -expand /packet_inject_tb/in_valid
add wave -noupdate -expand /packet_inject_tb/in_ready
add wave -noupdate -radix hexadecimal /packet_inject_tb/aux_data
add wave -noupdate /packet_inject_tb/aux_last
add wave -noupdate /packet_inject_tb/aux_valid
add wave -noupdate /packet_inject_tb/aux_ready
add wave -noupdate /packet_inject_tb/aux_error
add wave -noupdate -divider {Output stream}
add wave -noupdate -radix hexadecimal /packet_inject_tb/out_data
add wave -noupdate /packet_inject_tb/out_last
add wave -noupdate /packet_inject_tb/out_valid
add wave -noupdate /packet_inject_tb/out_ready
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/packet_inject_tb/ref_data(2) {-height 15 -radix hexadecimal} /packet_inject_tb/ref_data(1) {-height 15 -radix hexadecimal} /packet_inject_tb/ref_data(0) {-height 15 -radix hexadecimal}} /packet_inject_tb/ref_data
add wave -noupdate -expand /packet_inject_tb/ref_last
add wave -noupdate -divider {UUT Internals}
add wave -noupdate -expand /packet_inject_tb/in_valid
add wave -noupdate -expand /packet_inject_tb/in_ready
add wave -noupdate /packet_inject_tb/uut/sel_state
add wave -noupdate /packet_inject_tb/uut/sel_change
add wave -noupdate -radix hexadecimal /packet_inject_tb/uut/mux_data
add wave -noupdate /packet_inject_tb/uut/mux_last
add wave -noupdate /packet_inject_tb/uut/mux_valid
add wave -noupdate /packet_inject_tb/uut/mux_ready
add wave -noupdate /packet_inject_tb/uut/len_watchdog
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {9199806 ns} 0}
configure wave -namecolwidth 278
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
WaveRestoreZoom {0 ns} {9660 us}
