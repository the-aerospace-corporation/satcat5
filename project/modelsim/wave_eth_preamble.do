# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Input stream}
add wave -noupdate -radix hexadecimal /eth_preamble_tb/in_data
add wave -noupdate /eth_preamble_tb/in_last
add wave -noupdate /eth_preamble_tb/in_valid
add wave -noupdate /eth_preamble_tb/in_ready
add wave -noupdate -radix unsigned /eth_preamble_tb/in_rep_rate
add wave -noupdate /eth_preamble_tb/in_rep_read
add wave -noupdate -divider {Output and Reference}
add wave -noupdate /eth_preamble_tb/ref_valid
add wave -noupdate -radix hexadecimal /eth_preamble_tb/ref_data
add wave -noupdate -radix hexadecimal /eth_preamble_tb/out_data
add wave -noupdate -radix unsigned /eth_preamble_tb/ref_repeat
add wave -noupdate -radix unsigned /eth_preamble_tb/out_repeat
add wave -noupdate /eth_preamble_tb/ref_last
add wave -noupdate /eth_preamble_tb/out_last
add wave -noupdate /eth_preamble_tb/out_write
add wave -noupdate /eth_preamble_tb/out_error
add wave -noupdate /eth_preamble_tb/out_count
add wave -noupdate -divider {Tx Internals}
add wave -noupdate -radix hexadecimal /eth_preamble_tb/uut_tx/fifo_data
add wave -noupdate /eth_preamble_tb/uut_tx/fifo_last
add wave -noupdate /eth_preamble_tb/uut_tx/fifo_valid
add wave -noupdate /eth_preamble_tb/uut_tx/fifo_read
add wave -noupdate -radix unsigned /eth_preamble_tb/uut_tx/rep_ctr
add wave -noupdate -radix unsigned /eth_preamble_tb/uut_tx/rep_max
add wave -noupdate /eth_preamble_tb/uut_tx/reg_ctr
add wave -noupdate -radix hexadecimal /eth_preamble_tb/uut_tx/reg_data
add wave -noupdate /eth_preamble_tb/uut_tx/reg_dv
add wave -noupdate /eth_preamble_tb/uut_tx/reg_ready
add wave -noupdate -divider {Rx Internals}
add wave -noupdate /eth_preamble_tb/uut_rx/raw_lock
add wave -noupdate /eth_preamble_tb/uut_rx/raw_cken
add wave -noupdate -radix hexadecimal /eth_preamble_tb/uut_rx/raw_data
add wave -noupdate /eth_preamble_tb/uut_rx/raw_dv
add wave -noupdate /eth_preamble_tb/uut_rx/raw_err
add wave -noupdate -radix hexadecimal /eth_preamble_tb/uut_rx/rep_rate
add wave -noupdate -radix hexadecimal /eth_preamble_tb/uut_rx/out_data
add wave -noupdate /eth_preamble_tb/uut_rx/out_write
add wave -noupdate /eth_preamble_tb/uut_rx/out_last
add wave -noupdate /eth_preamble_tb/uut_rx/out_error
add wave -noupdate /eth_preamble_tb/uut_rx/reg_st
add wave -noupdate -radix hexadecimal /eth_preamble_tb/uut_rx/reg_data
add wave -noupdate /eth_preamble_tb/uut_rx/reg_dv
add wave -noupdate /eth_preamble_tb/uut_rx/reg_err
add wave -noupdate -radix unsigned /eth_preamble_tb/uut_rx/reg_ctr
add wave -noupdate -radix unsigned /eth_preamble_tb/uut_rx/reg_rpt
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {2099792563 ps} 0}
configure wave -namecolwidth 233
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
WaveRestoreZoom {84382791 ps} {100821959 ps}
