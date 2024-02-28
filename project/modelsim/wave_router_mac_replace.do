# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test control}
add wave -noupdate /router_mac_replace_tb/test_idx_hi
add wave -noupdate /router_mac_replace_tb/test_idx_lo
add wave -noupdate /router_mac_replace_tb/test_rate_in
add wave -noupdate /router_mac_replace_tb/test_rate_out
add wave -noupdate /router_mac_replace_tb/test_rate_icmp
add wave -noupdate /router_mac_replace_tb/test_drop_ct
add wave -noupdate /router_mac_replace_tb/test_arp_match
add wave -noupdate -divider {Input Stream}
add wave -noupdate -radix hexadecimal /router_mac_replace_tb/in_data
add wave -noupdate /router_mac_replace_tb/in_last
add wave -noupdate /router_mac_replace_tb/in_valid
add wave -noupdate /router_mac_replace_tb/in_ready
add wave -noupdate -divider {Output streams}
add wave -noupdate -radix hexadecimal /router_mac_replace_tb/ref_out_data
add wave -noupdate /router_mac_replace_tb/ref_out_last
add wave -noupdate /router_mac_replace_tb/ref_out_valid
add wave -noupdate /router_mac_replace_tb/ref_out_ready
add wave -noupdate -radix hexadecimal /router_mac_replace_tb/uut_out_data
add wave -noupdate /router_mac_replace_tb/uut_out_last
add wave -noupdate /router_mac_replace_tb/uut_out_valid
add wave -noupdate /router_mac_replace_tb/uut_out_ready
add wave -noupdate -radix hexadecimal /router_mac_replace_tb/ref_icmp_data
add wave -noupdate /router_mac_replace_tb/ref_icmp_last
add wave -noupdate /router_mac_replace_tb/ref_icmp_valid
add wave -noupdate /router_mac_replace_tb/ref_icmp_ready
add wave -noupdate -radix hexadecimal /router_mac_replace_tb/uut_icmp_data
add wave -noupdate /router_mac_replace_tb/uut_icmp_last
add wave -noupdate /router_mac_replace_tb/uut_icmp_valid
add wave -noupdate /router_mac_replace_tb/uut_icmp_ready
add wave -noupdate /router_mac_replace_tb/uut_pkt_drop
add wave -noupdate /router_mac_replace_tb/uut_pkt_error
add wave -noupdate -divider {ARP Query/reply}
add wave -noupdate -radix hexadecimal /router_mac_replace_tb/query_addr
add wave -noupdate /router_mac_replace_tb/query_first
add wave -noupdate /router_mac_replace_tb/query_valid
add wave -noupdate /router_mac_replace_tb/query_ready
add wave -noupdate -radix hexadecimal /router_mac_replace_tb/reply_addr
add wave -noupdate /router_mac_replace_tb/reply_first
add wave -noupdate /router_mac_replace_tb/reply_match
add wave -noupdate /router_mac_replace_tb/reply_write
add wave -noupdate -divider {UUT internals}
add wave -noupdate -radix hexadecimal /router_mac_replace_tb/uut/inj_data
add wave -noupdate /router_mac_replace_tb/uut/inj_last
add wave -noupdate /router_mac_replace_tb/uut/inj_write
add wave -noupdate /router_mac_replace_tb/uut/inj_valid
add wave -noupdate /router_mac_replace_tb/uut/inj_ready
add wave -noupdate /router_mac_replace_tb/uut/inj_retry
add wave -noupdate /router_mac_replace_tb/uut/inj_error
add wave -noupdate /router_mac_replace_tb/uut/parse_bct
add wave -noupdate -radix hexadecimal /router_mac_replace_tb/uut/parse_cmd
add wave -noupdate /router_mac_replace_tb/uut/parse_rdy
add wave -noupdate /router_mac_replace_tb/uut/parse_drop
add wave -noupdate /router_mac_replace_tb/uut/dfifo_valid
add wave -noupdate /router_mac_replace_tb/uut/dfifo_read
add wave -noupdate /router_mac_replace_tb/uut/cfifo_valid
add wave -noupdate /router_mac_replace_tb/uut/cfifo_read
add wave -noupdate /router_mac_replace_tb/uut/mfifo_match
add wave -noupdate /router_mac_replace_tb/uut/mfifo_valid
add wave -noupdate /router_mac_replace_tb/uut/mfifo_read
add wave -noupdate /router_mac_replace_tb/uut/mfifo_skip
add wave -noupdate /router_mac_replace_tb/uut/mfifo_desync
add wave -noupdate -radix hexadecimal /router_mac_replace_tb/uut/fwd_data
add wave -noupdate /router_mac_replace_tb/uut/fwd_last
add wave -noupdate /router_mac_replace_tb/uut/fwd_write
add wave -noupdate /router_mac_replace_tb/uut/fwd_hempty
add wave -noupdate /router_mac_replace_tb/uut/fwd_bct
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {190390 ns} 0}
configure wave -namecolwidth 248
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
WaveRestoreZoom {188097 ns} {194689 ns}
