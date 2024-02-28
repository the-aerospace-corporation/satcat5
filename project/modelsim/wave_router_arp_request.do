# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test control}
add wave -noupdate /router_arp_request_tb/test_idx
add wave -noupdate /router_arp_request_tb/rate_in
add wave -noupdate /router_arp_request_tb/rate_out
add wave -noupdate /router_arp_request_tb/req_start
add wave -noupdate /router_arp_request_tb/req_busy
add wave -noupdate -radix hexadecimal /router_arp_request_tb/req_ipaddr
add wave -noupdate /router_arp_request_tb/arp_rdy
add wave -noupdate -radix hexadecimal /router_arp_request_tb/arp_dst
add wave -noupdate -radix hexadecimal /router_arp_request_tb/arp_src
add wave -noupdate -radix hexadecimal /router_arp_request_tb/arp_sha
add wave -noupdate -radix hexadecimal /router_arp_request_tb/arp_spa
add wave -noupdate -radix hexadecimal /router_arp_request_tb/arp_tha
add wave -noupdate -radix hexadecimal /router_arp_request_tb/arp_tpa
add wave -noupdate -divider {Request interface}
add wave -noupdate /router_arp_request_tb/cmd_first
add wave -noupdate -radix hexadecimal /router_arp_request_tb/cmd_byte
add wave -noupdate /router_arp_request_tb/cmd_write
add wave -noupdate -divider {Network interface}
add wave -noupdate -radix hexadecimal /router_arp_request_tb/pkt_tx_data
add wave -noupdate /router_arp_request_tb/pkt_tx_last
add wave -noupdate /router_arp_request_tb/pkt_tx_valid
add wave -noupdate /router_arp_request_tb/pkt_tx_ready
add wave -noupdate -divider {UUT Internals}
add wave -noupdate -radix hexadecimal /router_arp_request_tb/uut/next_addr
add wave -noupdate /router_arp_request_tb/uut/next_start
add wave -noupdate /router_arp_request_tb/uut/next_valid
add wave -noupdate /router_arp_request_tb/uut/next_ready
add wave -noupdate /router_arp_request_tb/uut/hist_wrnext
add wave -noupdate /router_arp_request_tb/uut/hist_wrzero
add wave -noupdate /router_arp_request_tb/uut/scan_state
add wave -noupdate /router_arp_request_tb/uut/scan_rdidx
add wave -noupdate /router_arp_request_tb/uut/scan_done
add wave -noupdate /router_arp_request_tb/uut/scan_fail
add wave -noupdate /router_arp_request_tb/uut/scan_flush
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {885 ns} 0}
configure wave -namecolwidth 240
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
WaveRestoreZoom {0 ns} {105 us}
