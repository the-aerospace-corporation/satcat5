# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {UUT0 Stimulus}
add wave -noupdate /ptp_ingress_tb/uut0/test_index
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/in_data
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/in_nlast
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/in_write
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_pmsg
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_tlv0
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_tlv1
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_tlv2
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_tlv3
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_tlv4
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_tlv5
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_tlv6
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_tlv7
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_valid
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_ready
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/out_rcvd
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/ref_pmsg
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/ref_tlv0
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/ref_tlv1
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/ref_tlv2
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/ref_tlv3
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/ref_tlv4
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/ref_tlv5
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/ref_tlv6
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/ref_tlv7
add wave -noupdate -divider {UUT0 Internals}
add wave -noupdate /ptp_ingress_tb/uut0/uut/in_wcount
add wave -noupdate /ptp_ingress_tb/uut0/uut/parse_run
add wave -noupdate /ptp_ingress_tb/uut0/uut/parse_tnext
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/uut/parse_pmsg
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/uut/parse_tlv0
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/uut/parse_tlv1
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/uut/parse_tlv2
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/uut/parse_tlv3
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/uut/parse_tlv4
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/uut/parse_tlv5
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/uut/parse_tlv6
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut0/uut/parse_tlv7
add wave -noupdate /ptp_ingress_tb/uut0/uut/fifo_write
add wave -noupdate -divider {UUT1 Stimulus}
add wave -noupdate /ptp_ingress_tb/uut1/test_index
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/in_data
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/in_nlast
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/in_write
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_pmsg
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_tlv0
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_tlv1
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_tlv2
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_tlv3
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_tlv4
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_tlv5
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_tlv6
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_tlv7
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_valid
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_ready
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/out_rcvd
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/ref_pmsg
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/ref_tlv0
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/ref_tlv1
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/ref_tlv2
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/ref_tlv3
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/ref_tlv4
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/ref_tlv5
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/ref_tlv6
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/ref_tlv7
add wave -noupdate -divider {UUT1 Internals}
add wave -noupdate /ptp_ingress_tb/uut1/uut/in_wcount
add wave -noupdate /ptp_ingress_tb/uut1/uut/parse_run
add wave -noupdate /ptp_ingress_tb/uut1/uut/parse_tnext
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/uut/parse_pmsg
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/uut/parse_tlv0
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/uut/parse_tlv1
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/uut/parse_tlv2
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/uut/parse_tlv3
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/uut/parse_tlv4
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/uut/parse_tlv5
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/uut/parse_tlv6
add wave -noupdate -radix hexadecimal /ptp_ingress_tb/uut1/uut/parse_tlv7
add wave -noupdate /ptp_ingress_tb/uut1/uut/fifo_write
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {4394242199 ps} 0}
configure wave -namecolwidth 284
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
WaveRestoreZoom {0 ps} {13755 us}
