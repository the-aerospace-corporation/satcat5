# Copyright 2019, 2021 The Aerospace Corporation
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
add wave -noupdate -divider {U1 Test state}
add wave -noupdate /fifo_packet_tb/u1/test_idx
add wave -noupdate /fifo_packet_tb/u1/in_index
add wave -noupdate /fifo_packet_tb/u1/out_index
add wave -noupdate /fifo_packet_tb/u1/in_rate
add wave -noupdate /fifo_packet_tb/u1/mid_rate
add wave -noupdate /fifo_packet_tb/u1/out_rate
add wave -noupdate /fifo_packet_tb/u1/reset_p
add wave -noupdate /fifo_packet_tb/u1/in_ovr_ok
add wave -noupdate /fifo_packet_tb/u1/in_overflow
add wave -noupdate /fifo_packet_tb/u1/mid_ovr_ok
add wave -noupdate /fifo_packet_tb/u1/mid_overflow
add wave -noupdate -divider {U1 Input Data}
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u1/in_data
add wave -noupdate /fifo_packet_tb/u1/in_last_com
add wave -noupdate /fifo_packet_tb/u1/in_last_rev
add wave -noupdate /fifo_packet_tb/u1/in_write
add wave -noupdate -divider {U1 Middle Data}
add wave -noupdate /fifo_packet_tb/u1/mid_nlast
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u1/mid_data
add wave -noupdate /fifo_packet_tb/u1/mid_last
add wave -noupdate /fifo_packet_tb/u1/mid_write
add wave -noupdate -divider {U1 Output data}
add wave -noupdate /fifo_packet_tb/u1/out_total
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u1/out_ref
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u1/out_data
add wave -noupdate /fifo_packet_tb/u1/out_last
add wave -noupdate /fifo_packet_tb/u1/out_valid
add wave -noupdate /fifo_packet_tb/u1/out_ready
add wave -noupdate -divider {U1 First FIFO}
add wave -noupdate /fifo_packet_tb/u1/uut1/free_words
add wave -noupdate -radix unsigned /fifo_packet_tb/u1/uut1/new_words
add wave -noupdate /fifo_packet_tb/u1/uut1/in_last_commit
add wave -noupdate /fifo_packet_tb/u1/uut1/in_last_revert
add wave -noupdate /fifo_packet_tb/u1/uut1/wr_write
add wave -noupdate /fifo_packet_tb/u1/uut1/wr_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u1/uut1/wr_data
add wave -noupdate /fifo_packet_tb/u1/uut1/rd_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u1/uut1/rd_data
add wave -noupdate /fifo_packet_tb/u1/uut1/fifo_wr
add wave -noupdate /fifo_packet_tb/u1/uut1/out_pkt_rd
add wave -noupdate -divider {U1 Second FIFO}
add wave -noupdate /fifo_packet_tb/u1/uut2/free_words
add wave -noupdate -radix unsigned /fifo_packet_tb/u1/uut2/new_words
add wave -noupdate /fifo_packet_tb/u1/uut2/in_last_commit
add wave -noupdate /fifo_packet_tb/u1/uut2/in_last_revert
add wave -noupdate /fifo_packet_tb/u1/uut2/wr_write
add wave -noupdate /fifo_packet_tb/u1/uut2/wr_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u1/uut2/wr_data
add wave -noupdate /fifo_packet_tb/u1/uut2/rd_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u1/uut2/rd_data
add wave -noupdate /fifo_packet_tb/u1/uut2/fifo_wr
add wave -noupdate /fifo_packet_tb/u1/uut2/out_pkt_rd
add wave -noupdate -divider {U2 Test state}
add wave -noupdate /fifo_packet_tb/u2/test_idx
add wave -noupdate /fifo_packet_tb/u2/in_index
add wave -noupdate /fifo_packet_tb/u2/out_index
add wave -noupdate /fifo_packet_tb/u2/in_rate
add wave -noupdate /fifo_packet_tb/u2/mid_rate
add wave -noupdate /fifo_packet_tb/u2/out_rate
add wave -noupdate /fifo_packet_tb/u2/reset_p
add wave -noupdate /fifo_packet_tb/u2/in_ovr_ok
add wave -noupdate /fifo_packet_tb/u2/in_overflow
add wave -noupdate /fifo_packet_tb/u2/mid_ovr_ok
add wave -noupdate /fifo_packet_tb/u2/mid_overflow
add wave -noupdate -divider {U2 Input Data}
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u2/in_data
add wave -noupdate /fifo_packet_tb/u2/in_last_com
add wave -noupdate /fifo_packet_tb/u2/in_last_rev
add wave -noupdate /fifo_packet_tb/u2/in_write
add wave -noupdate -divider {U2 Middle Data}
add wave -noupdate /fifo_packet_tb/u2/mid_nlast
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u2/mid_data
add wave -noupdate /fifo_packet_tb/u2/mid_last
add wave -noupdate /fifo_packet_tb/u2/mid_write
add wave -noupdate -divider {U2 Output data}
add wave -noupdate /fifo_packet_tb/u2/out_total
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u2/out_ref
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u2/out_data
add wave -noupdate /fifo_packet_tb/u2/out_last
add wave -noupdate /fifo_packet_tb/u2/out_valid
add wave -noupdate /fifo_packet_tb/u2/out_ready
add wave -noupdate -divider {U2 First FIFO}
add wave -noupdate /fifo_packet_tb/u2/uut1/free_words
add wave -noupdate -radix unsigned /fifo_packet_tb/u2/uut1/new_words
add wave -noupdate /fifo_packet_tb/u2/uut1/in_last_commit
add wave -noupdate /fifo_packet_tb/u2/uut1/in_last_revert
add wave -noupdate /fifo_packet_tb/u2/uut1/wr_write
add wave -noupdate /fifo_packet_tb/u2/uut1/wr_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u2/uut1/wr_data
add wave -noupdate /fifo_packet_tb/u2/uut1/rd_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u2/uut1/rd_data
add wave -noupdate /fifo_packet_tb/u2/uut1/fifo_wr
add wave -noupdate /fifo_packet_tb/u2/uut1/out_pkt_rd
add wave -noupdate -divider {U2 Second FIFO}
add wave -noupdate /fifo_packet_tb/u2/uut2/free_words
add wave -noupdate -radix unsigned /fifo_packet_tb/u2/uut2/new_words
add wave -noupdate /fifo_packet_tb/u2/uut2/in_last_commit
add wave -noupdate /fifo_packet_tb/u2/uut2/in_last_revert
add wave -noupdate /fifo_packet_tb/u2/uut2/wr_write
add wave -noupdate /fifo_packet_tb/u2/uut2/wr_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u2/uut2/wr_data
add wave -noupdate /fifo_packet_tb/u2/uut2/rd_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u2/uut2/rd_data
add wave -noupdate /fifo_packet_tb/u2/uut2/fifo_wr
add wave -noupdate /fifo_packet_tb/u2/uut2/out_pkt_rd
add wave -noupdate -divider {U4 Input Data}
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u4/in_data
add wave -noupdate /fifo_packet_tb/u4/in_last_com
add wave -noupdate /fifo_packet_tb/u4/in_last_rev
add wave -noupdate /fifo_packet_tb/u4/in_write
add wave -noupdate -divider {U4 Middle Data}
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u4/mid_data
add wave -noupdate /fifo_packet_tb/u4/mid_nlast
add wave -noupdate /fifo_packet_tb/u4/mid_last
add wave -noupdate /fifo_packet_tb/u4/mid_write
add wave -noupdate -divider {U4 Output Data}
add wave -noupdate /fifo_packet_tb/u4/out_total
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u4/out_ref
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u4/out_data
add wave -noupdate /fifo_packet_tb/u4/out_last
add wave -noupdate /fifo_packet_tb/u4/out_valid
add wave -noupdate /fifo_packet_tb/u4/out_ready
add wave -noupdate -divider {U4 First FIFO}
add wave -noupdate /fifo_packet_tb/u4/uut1/free_words
add wave -noupdate -radix unsigned /fifo_packet_tb/u4/uut1/new_words
add wave -noupdate /fifo_packet_tb/u4/uut1/in_last_commit
add wave -noupdate /fifo_packet_tb/u4/uut1/in_last_revert
add wave -noupdate /fifo_packet_tb/u4/uut1/wr_write
add wave -noupdate /fifo_packet_tb/u4/uut1/wr_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u4/uut1/wr_data
add wave -noupdate /fifo_packet_tb/u4/uut1/rd_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u4/uut1/rd_data
add wave -noupdate /fifo_packet_tb/u4/uut1/fifo_wr
add wave -noupdate /fifo_packet_tb/u4/uut1/out_pkt_rd
add wave -noupdate -divider {U4 Second FIFO}
add wave -noupdate /fifo_packet_tb/u4/uut2/free_words
add wave -noupdate -radix unsigned /fifo_packet_tb/u4/uut2/new_words
add wave -noupdate /fifo_packet_tb/u4/uut2/in_last_commit
add wave -noupdate /fifo_packet_tb/u4/uut2/in_last_revert
add wave -noupdate /fifo_packet_tb/u4/uut2/wr_write
add wave -noupdate /fifo_packet_tb/u4/uut2/wr_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u4/uut2/wr_data
add wave -noupdate /fifo_packet_tb/u4/uut2/rd_addr
add wave -noupdate -radix hexadecimal /fifo_packet_tb/u4/uut2/rd_data
add wave -noupdate /fifo_packet_tb/u4/uut2/fifo_wr
add wave -noupdate /fifo_packet_tb/u4/uut2/out_pkt_rd
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1009822942 ps} 0}
configure wave -namecolwidth 296
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
WaveRestoreZoom {0 ps} {2637558 ns}
