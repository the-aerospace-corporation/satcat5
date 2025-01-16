# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test Control}
add wave -noupdate /router2_table_tb/test_index
add wave -noupdate -radix hexadecimal /router2_table_tb/cfg_cmd
add wave -noupdate -radix hexadecimal /router2_table_tb/cfg_ack
add wave -noupdate -divider UUT
add wave -noupdate -radix hexadecimal /router2_table_tb/in_dst_ip
add wave -noupdate -radix hexadecimal /router2_table_tb/in_meta
add wave -noupdate /router2_table_tb/in_next
add wave -noupdate -radix hexadecimal /router2_table_tb/out_dst_ip
add wave -noupdate -radix hexadecimal /router2_table_tb/ref_dst_ip
add wave -noupdate -radix unsigned /router2_table_tb/out_dst_idx
add wave -noupdate -radix unsigned /router2_table_tb/ref_dst_idx
add wave -noupdate -radix hexadecimal /router2_table_tb/out_dst_mac
add wave -noupdate -radix hexadecimal /router2_table_tb/ref_dst_mac
add wave -noupdate /router2_table_tb/out_found
add wave -noupdate /router2_table_tb/ref_found
add wave -noupdate -radix hexadecimal /router2_table_tb/out_meta
add wave -noupdate -radix hexadecimal /router2_table_tb/ref_meta
add wave -noupdate /router2_table_tb/out_next
add wave -noupdate /router2_table_tb/ref_valid
add wave -noupdate -divider {Table Load}
add wave -noupdate /router2_table_tb/uut/u_tcam/cfg_clear
add wave -noupdate /router2_table_tb/uut/u_tcam/cfg_index
add wave -noupdate /router2_table_tb/uut/u_tcam/cfg_plen
add wave -noupdate -radix hexadecimal /router2_table_tb/uut/u_tcam/cfg_search
add wave -noupdate -radix hexadecimal /router2_table_tb/uut/u_tcam/cfg_result
add wave -noupdate /router2_table_tb/uut/u_tcam/cfg_valid
add wave -noupdate /router2_table_tb/uut/u_tcam/cfg_ready
add wave -noupdate /router2_table_tb/uut/cpu_busy
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {429056 ps} 0}
configure wave -namecolwidth 261
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
WaveRestoreZoom {3690472 ps} {4119528 ps}
