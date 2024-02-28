# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test Control}
add wave -noupdate /router_ip_gateway_tb/test_idx_hi
add wave -noupdate /router_ip_gateway_tb/test_idx_lo
add wave -noupdate /router_ip_gateway_tb/test_rate_in
add wave -noupdate /router_ip_gateway_tb/test_rate_out
add wave -noupdate /router_ip_gateway_tb/test_rate_icmp
add wave -noupdate /router_ip_gateway_tb/tst_out_last
add wave -noupdate /router_ip_gateway_tb/tst_out_write
add wave -noupdate /router_ip_gateway_tb/tst_icmp_last
add wave -noupdate /router_ip_gateway_tb/tst_icmp_write
add wave -noupdate /router_ip_gateway_tb/test_drop_ct
add wave -noupdate -divider {Input Stream}
add wave -noupdate -radix hexadecimal /router_ip_gateway_tb/in_data
add wave -noupdate /router_ip_gateway_tb/in_last
add wave -noupdate /router_ip_gateway_tb/in_valid
add wave -noupdate /router_ip_gateway_tb/in_ready
add wave -noupdate /router_ip_gateway_tb/in_drop
add wave -noupdate -divider {Output Stream}
add wave -noupdate -radix hexadecimal /router_ip_gateway_tb/ref_out_data
add wave -noupdate /router_ip_gateway_tb/ref_out_last
add wave -noupdate /router_ip_gateway_tb/ref_out_valid
add wave -noupdate /router_ip_gateway_tb/ref_out_ready
add wave -noupdate -radix hexadecimal /router_ip_gateway_tb/uut_out_data
add wave -noupdate /router_ip_gateway_tb/uut_out_last
add wave -noupdate /router_ip_gateway_tb/uut_out_valid
add wave -noupdate /router_ip_gateway_tb/uut_out_ready
add wave -noupdate -divider {ICMP Stream}
add wave -noupdate -radix hexadecimal /router_ip_gateway_tb/ref_icmp_data
add wave -noupdate /router_ip_gateway_tb/ref_icmp_last
add wave -noupdate /router_ip_gateway_tb/ref_icmp_valid
add wave -noupdate /router_ip_gateway_tb/ref_icmp_ready
add wave -noupdate -radix hexadecimal /router_ip_gateway_tb/uut_icmp_data
add wave -noupdate /router_ip_gateway_tb/uut_icmp_last
add wave -noupdate /router_ip_gateway_tb/uut_icmp_valid
add wave -noupdate /router_ip_gateway_tb/uut_icmp_ready
add wave -noupdate -divider {UUT Internals}
add wave -noupdate /router_ip_gateway_tb/uut/parse_bct
add wave -noupdate -radix hexadecimal /router_ip_gateway_tb/uut/parse_cmd
add wave -noupdate /router_ip_gateway_tb/uut/parse_rdy
add wave -noupdate /router_ip_gateway_tb/uut/parse_done
add wave -noupdate /router_ip_gateway_tb/uut/parse_rem
add wave -noupdate -radix hexadecimal /router_ip_gateway_tb/uut/parse_sum
add wave -noupdate -radix hexadecimal /router_ip_gateway_tb/uut/cmd_data
add wave -noupdate /router_ip_gateway_tb/uut/cmd_valid
add wave -noupdate /router_ip_gateway_tb/uut/cmd_rd
add wave -noupdate -radix hexadecimal /router_ip_gateway_tb/uut/dat_data
add wave -noupdate /router_ip_gateway_tb/uut/dat_last
add wave -noupdate /router_ip_gateway_tb/uut/dat_valid
add wave -noupdate /router_ip_gateway_tb/uut/dat_rd
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {80179 ns} 0}
configure wave -namecolwidth 238
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
WaveRestoreZoom {79975 ns} {80415 ns}
