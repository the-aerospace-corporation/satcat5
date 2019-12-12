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
add wave -noupdate /port_rmii_tb/reset_p
add wave -noupdate -divider A2B
add wave -noupdate /port_rmii_tb/a2b_data
add wave -noupdate /port_rmii_tb/a2b_en
add wave -noupdate /port_rmii_tb/a2b_er
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_rmii_tb/rxdata_a.clk {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_a.data {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_a.last {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_a.write {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_a.rxerr {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_a.reset_p {-height 15 -radix hexadecimal}} /port_rmii_tb/rxdata_a
add wave -noupdate -radix hexadecimal /port_rmii_tb/u_src_b2a/ref_data
add wave -noupdate /port_rmii_tb/u_src_b2a/ref_last
add wave -noupdate /port_rmii_tb/u_src_b2a/rcvd_pkt
add wave -noupdate -divider B2A
add wave -noupdate /port_rmii_tb/b2a_data
add wave -noupdate /port_rmii_tb/b2a_en
add wave -noupdate /port_rmii_tb/b2a_er
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_rmii_tb/rxdata_b.clk {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_b.data {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_b.last {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_b.write {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_b.rxerr {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_b.reset_p {-height 15 -radix hexadecimal}} /port_rmii_tb/rxdata_b
add wave -noupdate -radix hexadecimal /port_rmii_tb/u_src_a2b/ref_data
add wave -noupdate /port_rmii_tb/u_src_a2b/ref_last
add wave -noupdate /port_rmii_tb/u_src_a2b/rcvd_pkt
add wave -noupdate -divider {Internals A}
add wave -noupdate /port_rmii_tb/uut_a/u_amble_rx/raw_lock
add wave -noupdate /port_rmii_tb/uut_a/u_amble_rx/raw_cken
add wave -noupdate -radix hexadecimal /port_rmii_tb/uut_a/u_amble_rx/raw_data
add wave -noupdate /port_rmii_tb/uut_a/u_amble_rx/raw_dv
add wave -noupdate /port_rmii_tb/uut_a/u_amble_rx/raw_err
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {10537571593 ps} 0}
configure wave -namecolwidth 293
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
WaveRestoreZoom {5432005453 ps} {33398315503 ps}
