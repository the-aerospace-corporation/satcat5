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
add wave -noupdate /port_serial_i2c_tb/i2c_sclk_o
add wave -noupdate /port_serial_i2c_tb/i2c_sdata_o
add wave -noupdate /port_serial_i2c_tb/i2c_sclk_i
add wave -noupdate /port_serial_i2c_tb/i2c_sdata_i
add wave -noupdate /port_serial_i2c_tb/ext_pause
add wave -noupdate /port_serial_i2c_tb/u_src_a2b/rcvd_pkt
add wave -noupdate /port_serial_i2c_tb/u_src_a2b/rxdone
add wave -noupdate /port_serial_i2c_tb/u_src_b2a/rcvd_pkt
add wave -noupdate /port_serial_i2c_tb/u_src_b2a/rxdone
add wave -noupdate -divider UUT-A
add wave -noupdate /port_serial_i2c_tb/uut_a/p_ctrl/ctrl_state
add wave -noupdate /port_serial_i2c_tb/uut_a/p_ctrl/ctrl_count
add wave -noupdate -radix hexadecimal /port_serial_i2c_tb/uut_a/i2c_opcode
add wave -noupdate -radix hexadecimal /port_serial_i2c_tb/uut_a/i2c_txdata
add wave -noupdate /port_serial_i2c_tb/uut_a/i2c_txvalid
add wave -noupdate /port_serial_i2c_tb/uut_a/i2c_txready
add wave -noupdate /port_serial_i2c_tb/uut_a/i2c_txwren
add wave -noupdate -radix hexadecimal /port_serial_i2c_tb/uut_a/i2c_rxdata
add wave -noupdate /port_serial_i2c_tb/uut_a/i2c_rxwrite
add wave -noupdate /port_serial_i2c_tb/uut_a/i2c_noack
add wave -noupdate -radix hexadecimal /port_serial_i2c_tb/uut_a/enc_data
add wave -noupdate /port_serial_i2c_tb/uut_a/enc_valid
add wave -noupdate /port_serial_i2c_tb/uut_a/enc_ready
add wave -noupdate -divider UUT-B
add wave -noupdate /port_serial_i2c_tb/uut_b/u_i2c/i2c_state
add wave -noupdate -radix hexadecimal /port_serial_i2c_tb/uut_b/i2c_rxdata
add wave -noupdate /port_serial_i2c_tb/uut_b/i2c_rxwrite
add wave -noupdate /port_serial_i2c_tb/uut_b/i2c_rxstart
add wave -noupdate /port_serial_i2c_tb/uut_b/i2c_rxrdreq
add wave -noupdate /port_serial_i2c_tb/uut_b/i2c_rxstop
add wave -noupdate -radix hexadecimal /port_serial_i2c_tb/uut_b/i2c_txdata
add wave -noupdate /port_serial_i2c_tb/uut_b/i2c_txvalid
add wave -noupdate /port_serial_i2c_tb/uut_b/i2c_txready
add wave -noupdate -radix hexadecimal /port_serial_i2c_tb/uut_b/enc_data
add wave -noupdate /port_serial_i2c_tb/uut_b/enc_valid
add wave -noupdate /port_serial_i2c_tb/uut_b/enc_ready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {44466 ns} 0}
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
WaveRestoreZoom {0 ns} {656256 ns}
