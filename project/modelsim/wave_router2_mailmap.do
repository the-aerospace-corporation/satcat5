# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider UUT0
add wave -noupdate /router2_mailmap_tb/uut0/test_index
add wave -noupdate -radix binary /router2_mailmap_tb/uut0/ref_keep
add wave -noupdate -radix hexadecimal /router2_mailmap_tb/uut0/rx_data
add wave -noupdate /router2_mailmap_tb/uut0/rx_nlast
add wave -noupdate /router2_mailmap_tb/uut0/rx_write
add wave -noupdate /router2_mailmap_tb/uut0/rx_commit
add wave -noupdate -radix hexadecimal /router2_mailmap_tb/uut0/tx_data
add wave -noupdate /router2_mailmap_tb/uut0/tx_nlast
add wave -noupdate /router2_mailmap_tb/uut0/tx_valid
add wave -noupdate /router2_mailmap_tb/uut0/tx_ready
add wave -noupdate -radix hexadecimal /router2_mailmap_tb/uut0/ref_data
add wave -noupdate /router2_mailmap_tb/uut0/ref_nlast
add wave -noupdate /router2_mailmap_tb/uut0/ref_valid
add wave -noupdate /router2_mailmap_tb/uut0/ref_ready
add wave -noupdate -radix binary /router2_mailmap_tb/uut0/tx_keep
add wave -noupdate -radix hexadecimal /router2_mailmap_tb/uut0/cfg_cmd
add wave -noupdate -radix hexadecimal /router2_mailmap_tb/uut0/cfg_ack
add wave -noupdate -divider UUT1
add wave -noupdate /router2_mailmap_tb/uut1/test_index
add wave -noupdate -radix binary /router2_mailmap_tb/uut1/ref_keep
add wave -noupdate -radix hexadecimal /router2_mailmap_tb/uut1/rx_data
add wave -noupdate /router2_mailmap_tb/uut1/rx_nlast
add wave -noupdate /router2_mailmap_tb/uut1/rx_write
add wave -noupdate /router2_mailmap_tb/uut1/rx_commit
add wave -noupdate -radix hexadecimal /router2_mailmap_tb/uut1/tx_data
add wave -noupdate /router2_mailmap_tb/uut1/tx_nlast
add wave -noupdate /router2_mailmap_tb/uut1/tx_valid
add wave -noupdate /router2_mailmap_tb/uut1/tx_ready
add wave -noupdate -radix binary /router2_mailmap_tb/uut1/tx_keep
add wave -noupdate -radix hexadecimal /router2_mailmap_tb/uut1/ref_data
add wave -noupdate /router2_mailmap_tb/uut1/ref_nlast
add wave -noupdate /router2_mailmap_tb/uut1/ref_valid
add wave -noupdate /router2_mailmap_tb/uut1/ref_ready
add wave -noupdate -radix hexadecimal /router2_mailmap_tb/uut1/cfg_cmd
add wave -noupdate -radix hexadecimal /router2_mailmap_tb/uut1/cfg_ack
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {30972447 ps} 0}
configure wave -namecolwidth 222
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
