# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test Signals}
add wave -noupdate -radix hexadecimal /config_send_status_tb/ref_data
add wave -noupdate -radix hexadecimal /config_send_status_tb/out_data
add wave -noupdate /config_send_status_tb/out_last
add wave -noupdate /config_send_status_tb/out_valid
add wave -noupdate /config_send_status_tb/out_ready
add wave -noupdate /config_send_status_tb/out_rate
add wave -noupdate -divider {UUT internals}
add wave -noupdate /config_send_status_tb/p_chk/byte_idx
add wave -noupdate /config_send_status_tb/uut/p_msg/byte_idx
add wave -noupdate /config_send_status_tb/uut/msg_start
add wave -noupdate -radix hexadecimal /config_send_status_tb/uut/msg_data
add wave -noupdate /config_send_status_tb/uut/msg_last
add wave -noupdate /config_send_status_tb/uut/msg_valid
add wave -noupdate /config_send_status_tb/uut/msg_ready
add wave -noupdate -radix hexadecimal /config_send_status_tb/uut/u_fcs/fcs_data
add wave -noupdate /config_send_status_tb/uut/u_fcs/fcs_last
add wave -noupdate /config_send_status_tb/uut/u_fcs/fcs_valid
add wave -noupdate /config_send_status_tb/uut/u_fcs/fcs_ready
add wave -noupdate /config_send_status_tb/uut/u_fcs/fcs_ovr
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {31085 ns} 0}
configure wave -namecolwidth 276
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
WaveRestoreZoom {31052 ns} {31258 ns}
