# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider UUT0
add wave -noupdate /fifo_pktmeta_tb/test0/test_index
add wave -noupdate -radix unsigned /fifo_pktmeta_tb/test0/in_pktlen
add wave -noupdate /fifo_pktmeta_tb/test0/in_pktvalid
add wave -noupdate /fifo_pktmeta_tb/test0/in_pktready
add wave -noupdate -radix unsigned /fifo_pktmeta_tb/test0/ref_pktlen
add wave -noupdate /fifo_pktmeta_tb/test0/ref_pktvalid
add wave -noupdate /fifo_pktmeta_tb/test0/ref_pktready
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test0/in_data
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test0/in_meta
add wave -noupdate /fifo_pktmeta_tb/test0/in_nlast
add wave -noupdate /fifo_pktmeta_tb/test0/in_valid
add wave -noupdate /fifo_pktmeta_tb/test0/in_ready
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test0/ref_data
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test0/ref_meta
add wave -noupdate /fifo_pktmeta_tb/test0/ref_nlast
add wave -noupdate /fifo_pktmeta_tb/test0/ref_valid
add wave -noupdate /fifo_pktmeta_tb/test0/ref_next
add wave -noupdate /fifo_pktmeta_tb/test0/uut_error
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test0/out_data
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test0/out_meta
add wave -noupdate -radix unsigned /fifo_pktmeta_tb/test0/out_pktlen
add wave -noupdate /fifo_pktmeta_tb/test0/out_nlast
add wave -noupdate /fifo_pktmeta_tb/test0/out_valid
add wave -noupdate /fifo_pktmeta_tb/test0/out_ready
add wave -noupdate -divider {UUT0 Internals}
add wave -noupdate /fifo_pktmeta_tb/test0/uut/data_error
add wave -noupdate /fifo_pktmeta_tb/test0/uut/data_last
add wave -noupdate /fifo_pktmeta_tb/test0/uut/data_ready
add wave -noupdate /fifo_pktmeta_tb/test0/uut/data_valid
add wave -noupdate /fifo_pktmeta_tb/test0/uut/data_write
add wave -noupdate /fifo_pktmeta_tb/test0/uut/meta_error
add wave -noupdate /fifo_pktmeta_tb/test0/uut/meta_nlast
add wave -noupdate /fifo_pktmeta_tb/test0/uut/meta_ready
add wave -noupdate /fifo_pktmeta_tb/test0/uut/meta_valid
add wave -noupdate /fifo_pktmeta_tb/test0/uut/out_last
add wave -noupdate -divider UUT1
add wave -noupdate /fifo_pktmeta_tb/test1/test_index
add wave -noupdate -radix unsigned /fifo_pktmeta_tb/test1/in_pktlen
add wave -noupdate /fifo_pktmeta_tb/test1/in_pktvalid
add wave -noupdate /fifo_pktmeta_tb/test1/in_pktready
add wave -noupdate -radix unsigned /fifo_pktmeta_tb/test1/ref_pktlen
add wave -noupdate /fifo_pktmeta_tb/test1/ref_pktvalid
add wave -noupdate /fifo_pktmeta_tb/test1/ref_pktready
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test1/in_data
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test1/in_meta
add wave -noupdate /fifo_pktmeta_tb/test1/in_nlast
add wave -noupdate /fifo_pktmeta_tb/test1/in_valid
add wave -noupdate /fifo_pktmeta_tb/test1/in_ready
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test1/ref_data
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test1/ref_meta
add wave -noupdate /fifo_pktmeta_tb/test1/ref_nlast
add wave -noupdate /fifo_pktmeta_tb/test1/ref_valid
add wave -noupdate /fifo_pktmeta_tb/test1/ref_next
add wave -noupdate /fifo_pktmeta_tb/test1/uut_error
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test1/out_data
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test1/out_meta
add wave -noupdate -radix unsigned /fifo_pktmeta_tb/test1/out_pktlen
add wave -noupdate /fifo_pktmeta_tb/test1/out_nlast
add wave -noupdate /fifo_pktmeta_tb/test1/out_valid
add wave -noupdate /fifo_pktmeta_tb/test1/out_ready
add wave -noupdate -divider {UUT1 Internals}
add wave -noupdate /fifo_pktmeta_tb/test1/uut/data_error
add wave -noupdate /fifo_pktmeta_tb/test1/uut/data_last
add wave -noupdate /fifo_pktmeta_tb/test1/uut/data_ready
add wave -noupdate /fifo_pktmeta_tb/test1/uut/data_valid
add wave -noupdate /fifo_pktmeta_tb/test1/uut/data_write
add wave -noupdate /fifo_pktmeta_tb/test1/uut/meta_error
add wave -noupdate /fifo_pktmeta_tb/test1/uut/meta_nlast
add wave -noupdate /fifo_pktmeta_tb/test1/uut/meta_ready
add wave -noupdate /fifo_pktmeta_tb/test1/uut/meta_valid
add wave -noupdate /fifo_pktmeta_tb/test1/uut/out_last
add wave -noupdate -divider UUT2
add wave -noupdate /fifo_pktmeta_tb/test2/test_index
add wave -noupdate -radix unsigned /fifo_pktmeta_tb/test2/in_pktlen
add wave -noupdate /fifo_pktmeta_tb/test2/in_pktvalid
add wave -noupdate /fifo_pktmeta_tb/test2/in_pktready
add wave -noupdate -radix unsigned /fifo_pktmeta_tb/test2/ref_pktlen
add wave -noupdate /fifo_pktmeta_tb/test2/ref_pktvalid
add wave -noupdate /fifo_pktmeta_tb/test2/ref_pktready
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test2/in_data
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test2/in_meta
add wave -noupdate /fifo_pktmeta_tb/test2/in_nlast
add wave -noupdate /fifo_pktmeta_tb/test2/in_valid
add wave -noupdate /fifo_pktmeta_tb/test2/in_ready
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test2/ref_data
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test2/ref_meta
add wave -noupdate /fifo_pktmeta_tb/test2/ref_nlast
add wave -noupdate /fifo_pktmeta_tb/test2/ref_valid
add wave -noupdate /fifo_pktmeta_tb/test2/ref_next
add wave -noupdate /fifo_pktmeta_tb/test2/uut_error
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test2/out_data
add wave -noupdate -radix hexadecimal /fifo_pktmeta_tb/test2/out_meta
add wave -noupdate -radix unsigned /fifo_pktmeta_tb/test2/out_pktlen
add wave -noupdate /fifo_pktmeta_tb/test2/out_nlast
add wave -noupdate /fifo_pktmeta_tb/test2/out_valid
add wave -noupdate /fifo_pktmeta_tb/test2/out_ready
add wave -noupdate -divider {UUT2 Internals}
add wave -noupdate /fifo_pktmeta_tb/test2/uut/data_error
add wave -noupdate /fifo_pktmeta_tb/test2/uut/data_last
add wave -noupdate /fifo_pktmeta_tb/test2/uut/data_ready
add wave -noupdate /fifo_pktmeta_tb/test2/uut/data_valid
add wave -noupdate /fifo_pktmeta_tb/test2/uut/data_write
add wave -noupdate /fifo_pktmeta_tb/test2/uut/meta_error
add wave -noupdate /fifo_pktmeta_tb/test2/uut/meta_nlast
add wave -noupdate /fifo_pktmeta_tb/test2/uut/meta_ready
add wave -noupdate /fifo_pktmeta_tb/test2/uut/meta_valid
add wave -noupdate /fifo_pktmeta_tb/test2/uut/out_last
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {76861511 ps} 0}
configure wave -namecolwidth 283
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
WaveRestoreZoom {0 ps} {105 us}
