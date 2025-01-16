# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider UUT0
add wave -noupdate /router2_gateway_tb/uut0/test_index
add wave -noupdate /router2_gateway_tb/uut0/test_regaddr
add wave -noupdate /router2_gateway_tb/uut0/test_rdcmd
add wave -noupdate /router2_gateway_tb/uut0/test_wrcmd
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/test_wdata
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/cfg_ack
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/in_data
add wave -noupdate /router2_gateway_tb/uut0/in_nlast
add wave -noupdate /router2_gateway_tb/uut0/in_valid
add wave -noupdate /router2_gateway_tb/uut0/in_ready
add wave -noupdate /router2_gateway_tb/uut0/in_empty
add wave -noupdate /router2_gateway_tb/uut0/in_psrc
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/out_data
add wave -noupdate /router2_gateway_tb/uut0/out_nlast
add wave -noupdate /router2_gateway_tb/uut0/out_valid
add wave -noupdate /router2_gateway_tb/uut0/out_ready
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/out_dstmac
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/out_srcmac
add wave -noupdate /router2_gateway_tb/uut0/out_pdst
add wave -noupdate /router2_gateway_tb/uut0/out_psrc
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/ref_data
add wave -noupdate /router2_gateway_tb/uut0/ref_nlast
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/ref_dstmac
add wave -noupdate /router2_gateway_tb/uut0/ref_pdst
add wave -noupdate /router2_gateway_tb/uut0/ref_psrc
add wave -noupdate /router2_gateway_tb/uut0/ref_empty
add wave -noupdate -divider {UUT0 Internals}
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/uut/dly_data
add wave -noupdate /router2_gateway_tb/uut0/uut/dly_nlast
add wave -noupdate /router2_gateway_tb/uut0/uut/dly_valid
add wave -noupdate /router2_gateway_tb/uut0/uut/dly_ready
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/uut/u_chksum/chk_data
add wave -noupdate /router2_gateway_tb/uut0/uut/u_chksum/chk_nlast
add wave -noupdate /router2_gateway_tb/uut0/uut/u_chksum/chk_write
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/uut/u_chksum/chk_accum
add wave -noupdate /router2_gateway_tb/uut0/uut/u_chksum/chk_final
add wave -noupdate /router2_gateway_tb/uut0/uut/u_chksum/chk_match
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/uut/chk_data
add wave -noupdate /router2_gateway_tb/uut0/uut/chk_psrc
add wave -noupdate /router2_gateway_tb/uut0/uut/chk_nlast
add wave -noupdate /router2_gateway_tb/uut0/uut/chk_write
add wave -noupdate /router2_gateway_tb/uut0/uut/chk_match
add wave -noupdate /router2_gateway_tb/uut0/uut/chk_error
add wave -noupdate /router2_gateway_tb/uut0/uut/chk_wcount
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/uut/pkt_dst_ip
add wave -noupdate /router2_gateway_tb/uut0/uut/pkt_mvec
add wave -noupdate /router2_gateway_tb/uut0/uut/pkt_next
add wave -noupdate /router2_gateway_tb/uut0/uut/pkt_done
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/uut/u_table/tcam_result
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/uut/u_table/tcam_found
add wave -noupdate -radix binary /router2_gateway_tb/uut0/uut/u_table/tcam_meta
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/uut/u_table/tcam_next
add wave -noupdate /router2_gateway_tb/uut0/uut/tbl_found
add wave -noupdate /router2_gateway_tb/uut0/uut/tbl_next
add wave -noupdate /router2_gateway_tb/uut0/uut/tbl_mvec
add wave -noupdate /router2_gateway_tb/uut0/uut/tbl_action
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/uut/tbl_dstmac
add wave -noupdate /router2_gateway_tb/uut0/uut/tbl_dstmask
add wave -noupdate /router2_gateway_tb/uut0/uut/tbl_shdn
add wave -noupdate /router2_gateway_tb/uut0/uut/tbl_pdst
add wave -noupdate -radix unsigned /router2_gateway_tb/uut0/uut/tbl_psrc
add wave -noupdate /router2_gateway_tb/uut0/uut/tbl_offload
add wave -noupdate -radix hexadecimal /router2_gateway_tb/uut0/uut/dst_mac
add wave -noupdate /router2_gateway_tb/uut0/uut/dst_mask
add wave -noupdate /router2_gateway_tb/uut0/uut/dst_next
add wave -noupdate /router2_gateway_tb/uut0/uut/dst_valid
add wave -noupdate /router2_gateway_tb/uut0/uut/dst_ready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 2} {2999895459 ps} 0}
configure wave -namecolwidth 315
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
WaveRestoreZoom {2999853881 ps} {3000007691 ps}
