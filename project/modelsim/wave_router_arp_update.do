# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test control}
add wave -noupdate /router_arp_update_tb/test_idx
add wave -noupdate /router_arp_update_tb/rate_in
add wave -noupdate /router_arp_update_tb/rate_out
add wave -noupdate /router_arp_update_tb/query_start
add wave -noupdate /router_arp_update_tb/query_type
add wave -noupdate /router_arp_update_tb/query_busy
add wave -noupdate -radix hexadecimal /router_arp_update_tb/query_sha
add wave -noupdate -radix hexadecimal /router_arp_update_tb/query_spa
add wave -noupdate -radix hexadecimal /router_arp_update_tb/query_tha
add wave -noupdate -radix hexadecimal /router_arp_update_tb/query_tpa
add wave -noupdate /router_arp_update_tb/rcvd_rdy
add wave -noupdate -radix hexadecimal /router_arp_update_tb/rcvd_ip
add wave -noupdate -radix hexadecimal /router_arp_update_tb/rcvd_mac
add wave -noupdate -divider {Network port}
add wave -noupdate -radix hexadecimal /router_arp_update_tb/pkt_rx_data
add wave -noupdate /router_arp_update_tb/pkt_rx_last
add wave -noupdate /router_arp_update_tb/pkt_rx_write
add wave -noupdate -divider {Update port}
add wave -noupdate -radix hexadecimal /router_arp_update_tb/update_addr
add wave -noupdate /router_arp_update_tb/update_first
add wave -noupdate /router_arp_update_tb/update_valid
add wave -noupdate /router_arp_update_tb/update_ready
add wave -noupdate /router_arp_update_tb/p_update/bcount
add wave -noupdate -divider Pre-parser
add wave -noupdate -radix hexadecimal /router_arp_update_tb/arp_rx_data
add wave -noupdate /router_arp_update_tb/arp_rx_first
add wave -noupdate /router_arp_update_tb/arp_rx_last
add wave -noupdate /router_arp_update_tb/arp_rx_write
add wave -noupdate -divider {UUT Internals}
add wave -noupdate /router_arp_update_tb/uut/cmd_state
add wave -noupdate /router_arp_update_tb/uut/cmd_busy
add wave -noupdate -radix hexadecimal /router_arp_update_tb/uut/cmd_addr
add wave -noupdate /router_arp_update_tb/uut/cmd_first
add wave -noupdate /router_arp_update_tb/uut/cmd_valid
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {999635 ns} 0}
configure wave -namecolwidth 282
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
WaveRestoreZoom {0 ns} {1050 us}
