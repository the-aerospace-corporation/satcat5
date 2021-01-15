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
add wave -noupdate -divider {Input stream}
add wave -noupdate -radix hexadecimal /fifo_bram_tb/test0/in_data
add wave -noupdate /fifo_bram_tb/test0/in_last
add wave -noupdate /fifo_bram_tb/test0/in_write
add wave -noupdate -divider {Reference stream}
add wave -noupdate -radix hexadecimal /fifo_bram_tb/test0/ref_data
add wave -noupdate /fifo_bram_tb/test0/ref_last
add wave -noupdate /fifo_bram_tb/test0/ref_full
add wave -noupdate /fifo_bram_tb/test0/ref_empty
add wave -noupdate /fifo_bram_tb/test0/ref_error
add wave -noupdate -divider {Output stream}
add wave -noupdate -radix hexadecimal /fifo_bram_tb/test0/out_data
add wave -noupdate /fifo_bram_tb/test0/out_last
add wave -noupdate /fifo_bram_tb/test0/out_valid
add wave -noupdate /fifo_bram_tb/test0/out_ready
add wave -noupdate /fifo_bram_tb/test0/fifo_error
add wave -noupdate /fifo_bram_tb/test0/fifo_empty
add wave -noupdate /fifo_bram_tb/test0/fifo_full
add wave -noupdate -divider {UUT0 State}
add wave -noupdate /fifo_bram_tb/test0/uut/fifo_wr_safe
add wave -noupdate -radix unsigned /fifo_bram_tb/test0/uut/fifo_wr_addr
add wave -noupdate -radix unsigned /fifo_bram_tb/test0/uut/fifo_rd_addr_d
add wave -noupdate -radix unsigned /fifo_bram_tb/test0/uut/fifo_rd_addr_q
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {10009739 ns} 0}
configure wave -namecolwidth 267
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
WaveRestoreZoom {0 ns} {10510500 ns}
