# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /fifo_repack_tb/test1/reset_p
add wave -noupdate -radix hexadecimal /fifo_repack_tb/test1/in_data
add wave -noupdate /fifo_repack_tb/test1/in_last
add wave -noupdate /fifo_repack_tb/test1/in_write
add wave -noupdate -radix hexadecimal /fifo_repack_tb/test1/ref_data
add wave -noupdate /fifo_repack_tb/test1/ref_nlast
add wave -noupdate /fifo_repack_tb/test1/ref_last
add wave -noupdate -radix hexadecimal /fifo_repack_tb/test1/out_data
add wave -noupdate /fifo_repack_tb/test1/out_nlast
add wave -noupdate /fifo_repack_tb/test1/out_last
add wave -noupdate /fifo_repack_tb/test1/out_write
add wave -noupdate -divider UUT2
add wave -noupdate -radix hexadecimal /fifo_repack_tb/test2/in_data
add wave -noupdate /fifo_repack_tb/test2/in_last
add wave -noupdate /fifo_repack_tb/test2/in_write
add wave -noupdate -radix hexadecimal /fifo_repack_tb/test2/ref_data
add wave -noupdate /fifo_repack_tb/test2/ref_nlast
add wave -noupdate /fifo_repack_tb/test2/ref_last
add wave -noupdate -radix hexadecimal /fifo_repack_tb/test2/out_data
add wave -noupdate /fifo_repack_tb/test2/out_nlast
add wave -noupdate /fifo_repack_tb/test2/out_last
add wave -noupdate /fifo_repack_tb/test2/out_write
add wave -noupdate -radix hexadecimal /fifo_repack_tb/test2/uut/sreg_data
add wave -noupdate /fifo_repack_tb/test2/uut/sreg_last
add wave -noupdate /fifo_repack_tb/test2/uut/sreg_lhot
add wave -noupdate /fifo_repack_tb/test2/uut/sreg_count
add wave -noupdate -divider UUT3
add wave -noupdate /fifo_repack_tb/test3/in_data
add wave -noupdate /fifo_repack_tb/test3/in_last
add wave -noupdate /fifo_repack_tb/test3/in_write
add wave -noupdate /fifo_repack_tb/test3/ref_data
add wave -noupdate /fifo_repack_tb/test3/ref_nlast
add wave -noupdate /fifo_repack_tb/test3/ref_last
add wave -noupdate /fifo_repack_tb/test3/out_data
add wave -noupdate /fifo_repack_tb/test3/out_nlast
add wave -noupdate /fifo_repack_tb/test3/out_last
add wave -noupdate /fifo_repack_tb/test3/out_write
add wave -noupdate /fifo_repack_tb/test3/uut/sreg_data
add wave -noupdate /fifo_repack_tb/test3/uut/sreg_last
add wave -noupdate /fifo_repack_tb/test3/uut/sreg_lhot
add wave -noupdate /fifo_repack_tb/test3/uut/sreg_count
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {68367056 ps} 0}
configure wave -namecolwidth 217
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
WaveRestoreZoom {66035156 ps} {84902344 ps}
