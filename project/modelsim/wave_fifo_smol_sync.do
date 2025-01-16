# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider Test0
add wave -noupdate /fifo_smol_sync_tb/test0/test_ok
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test0/in_data
add wave -noupdate /fifo_smol_sync_tb/test0/in_last
add wave -noupdate /fifo_smol_sync_tb/test0/in_write
add wave -noupdate /fifo_smol_sync_tb/test0/out_read
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test0/ref_data
add wave -noupdate /fifo_smol_sync_tb/test0/ref_last
add wave -noupdate /fifo_smol_sync_tb/test0/ref_full
add wave -noupdate /fifo_smol_sync_tb/test0/ref_empty
add wave -noupdate /fifo_smol_sync_tb/test0/ref_hfull
add wave -noupdate /fifo_smol_sync_tb/test0/ref_hempty
add wave -noupdate /fifo_smol_sync_tb/test0/ref_error
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test0/out_data
add wave -noupdate /fifo_smol_sync_tb/test0/out_last
add wave -noupdate /fifo_smol_sync_tb/test0/out_valid
add wave -noupdate /fifo_smol_sync_tb/test0/fifo_full
add wave -noupdate /fifo_smol_sync_tb/test0/fifo_empty
add wave -noupdate /fifo_smol_sync_tb/test0/fifo_hfull
add wave -noupdate /fifo_smol_sync_tb/test0/fifo_hempty
add wave -noupdate /fifo_smol_sync_tb/test0/fifo_error
add wave -noupdate -divider Test1
add wave -noupdate /fifo_smol_sync_tb/test1/test_ok
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test1/in_meta
add wave -noupdate /fifo_smol_sync_tb/test1/in_last
add wave -noupdate /fifo_smol_sync_tb/test1/in_write
add wave -noupdate /fifo_smol_sync_tb/test1/out_read
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test1/ref_meta
add wave -noupdate /fifo_smol_sync_tb/test1/ref_last
add wave -noupdate /fifo_smol_sync_tb/test1/ref_full
add wave -noupdate /fifo_smol_sync_tb/test1/ref_empty
add wave -noupdate /fifo_smol_sync_tb/test1/ref_hfull
add wave -noupdate /fifo_smol_sync_tb/test1/ref_hempty
add wave -noupdate /fifo_smol_sync_tb/test1/ref_error
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test1/out_meta
add wave -noupdate /fifo_smol_sync_tb/test1/out_last
add wave -noupdate /fifo_smol_sync_tb/test1/out_valid
add wave -noupdate /fifo_smol_sync_tb/test1/fifo_full
add wave -noupdate /fifo_smol_sync_tb/test1/fifo_empty
add wave -noupdate /fifo_smol_sync_tb/test1/fifo_hfull
add wave -noupdate /fifo_smol_sync_tb/test1/fifo_hempty
add wave -noupdate /fifo_smol_sync_tb/test1/fifo_error
add wave -noupdate -divider Test2
add wave -noupdate /fifo_smol_sync_tb/test2/test_ok
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test2/in_data
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test2/in_meta
add wave -noupdate /fifo_smol_sync_tb/test2/in_last
add wave -noupdate /fifo_smol_sync_tb/test2/in_write
add wave -noupdate /fifo_smol_sync_tb/test2/out_read
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test2/ref_data
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test2/ref_meta
add wave -noupdate /fifo_smol_sync_tb/test2/ref_last
add wave -noupdate /fifo_smol_sync_tb/test2/ref_full
add wave -noupdate /fifo_smol_sync_tb/test2/ref_empty
add wave -noupdate /fifo_smol_sync_tb/test2/ref_hfull
add wave -noupdate /fifo_smol_sync_tb/test2/ref_hempty
add wave -noupdate /fifo_smol_sync_tb/test2/ref_error
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test2/out_data
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test2/out_meta
add wave -noupdate /fifo_smol_sync_tb/test2/out_last
add wave -noupdate /fifo_smol_sync_tb/test2/out_valid
add wave -noupdate /fifo_smol_sync_tb/test2/fifo_full
add wave -noupdate /fifo_smol_sync_tb/test2/fifo_empty
add wave -noupdate /fifo_smol_sync_tb/test2/fifo_hfull
add wave -noupdate /fifo_smol_sync_tb/test2/fifo_hempty
add wave -noupdate /fifo_smol_sync_tb/test2/fifo_error
add wave -noupdate -divider Test3
add wave -noupdate /fifo_smol_sync_tb/test3/test_ok
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test3/in_data
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test3/in_meta
add wave -noupdate /fifo_smol_sync_tb/test3/in_last
add wave -noupdate /fifo_smol_sync_tb/test3/in_write
add wave -noupdate /fifo_smol_sync_tb/test3/out_read
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test3/ref_data
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test3/ref_meta
add wave -noupdate /fifo_smol_sync_tb/test3/ref_last
add wave -noupdate /fifo_smol_sync_tb/test3/ref_full
add wave -noupdate /fifo_smol_sync_tb/test3/ref_empty
add wave -noupdate /fifo_smol_sync_tb/test3/ref_hfull
add wave -noupdate /fifo_smol_sync_tb/test3/ref_hempty
add wave -noupdate /fifo_smol_sync_tb/test3/ref_error
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test3/out_data
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test3/out_meta
add wave -noupdate /fifo_smol_sync_tb/test3/out_last
add wave -noupdate /fifo_smol_sync_tb/test3/out_valid
add wave -noupdate /fifo_smol_sync_tb/test3/fifo_full
add wave -noupdate /fifo_smol_sync_tb/test3/fifo_empty
add wave -noupdate /fifo_smol_sync_tb/test3/fifo_hfull
add wave -noupdate /fifo_smol_sync_tb/test3/fifo_hempty
add wave -noupdate /fifo_smol_sync_tb/test3/fifo_error
add wave -noupdate -divider Test4
add wave -noupdate /fifo_smol_sync_tb/test4/test_ok
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test4/in_data
add wave -noupdate /fifo_smol_sync_tb/test4/in_last
add wave -noupdate /fifo_smol_sync_tb/test4/in_write_tmp
add wave -noupdate /fifo_smol_sync_tb/test4/in_write
add wave -noupdate /fifo_smol_sync_tb/test4/out_read_tmp
add wave -noupdate /fifo_smol_sync_tb/test4/out_read
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test4/ref_data
add wave -noupdate /fifo_smol_sync_tb/test4/ref_last
add wave -noupdate /fifo_smol_sync_tb/test4/ref_full
add wave -noupdate /fifo_smol_sync_tb/test4/ref_empty
add wave -noupdate /fifo_smol_sync_tb/test4/ref_hfull
add wave -noupdate /fifo_smol_sync_tb/test4/ref_hempty
add wave -noupdate /fifo_smol_sync_tb/test4/ref_error
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test4/out_data
add wave -noupdate /fifo_smol_sync_tb/test4/out_last
add wave -noupdate /fifo_smol_sync_tb/test4/out_valid
add wave -noupdate /fifo_smol_sync_tb/test4/fifo_full
add wave -noupdate /fifo_smol_sync_tb/test4/fifo_empty
add wave -noupdate /fifo_smol_sync_tb/test4/fifo_hfull
add wave -noupdate /fifo_smol_sync_tb/test4/fifo_hempty
add wave -noupdate /fifo_smol_sync_tb/test4/fifo_error
add wave -noupdate -divider Test5
add wave -noupdate /fifo_smol_sync_tb/test5/test_ok
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test5/in_meta
add wave -noupdate /fifo_smol_sync_tb/test5/in_last
add wave -noupdate /fifo_smol_sync_tb/test5/in_write
add wave -noupdate /fifo_smol_sync_tb/test5/out_read
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test5/ref_meta
add wave -noupdate /fifo_smol_sync_tb/test5/ref_last
add wave -noupdate /fifo_smol_sync_tb/test5/ref_full
add wave -noupdate /fifo_smol_sync_tb/test5/ref_empty
add wave -noupdate /fifo_smol_sync_tb/test5/ref_hfull
add wave -noupdate /fifo_smol_sync_tb/test5/ref_hempty
add wave -noupdate /fifo_smol_sync_tb/test5/ref_error
add wave -noupdate -radix hexadecimal /fifo_smol_sync_tb/test5/out_meta
add wave -noupdate /fifo_smol_sync_tb/test5/out_last
add wave -noupdate /fifo_smol_sync_tb/test5/out_valid
add wave -noupdate /fifo_smol_sync_tb/test5/fifo_full
add wave -noupdate /fifo_smol_sync_tb/test5/fifo_empty
add wave -noupdate /fifo_smol_sync_tb/test5/fifo_hfull
add wave -noupdate /fifo_smol_sync_tb/test5/fifo_hempty
add wave -noupdate /fifo_smol_sync_tb/test5/fifo_error
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {7216135 ps} 0}
configure wave -namecolwidth 320
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
WaveRestoreZoom {7193984 ps} {7276016 ps}
