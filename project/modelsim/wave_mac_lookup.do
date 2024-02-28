# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider UUT1
add wave -noupdate /mac_lookup_tb/uut1/pkt_count
add wave -noupdate /mac_lookup_tb/uut1/pkt_delay
add wave -noupdate /mac_lookup_tb/uut1/pkt_mode
add wave -noupdate /mac_lookup_tb/uut1/cfg_delay
add wave -noupdate /mac_lookup_tb/uut1/in_pdst
add wave -noupdate /mac_lookup_tb/uut1/mac_final
add wave -noupdate /mac_lookup_tb/uut1/ref_pdst
add wave -noupdate /mac_lookup_tb/uut1/ref_rd
add wave -noupdate /mac_lookup_tb/uut1/ref_valid
add wave -noupdate /mac_lookup_tb/uut1/in_time
add wave -noupdate /mac_lookup_tb/uut1/ref_time
add wave -noupdate /mac_lookup_tb/uut1/in_psrc
add wave -noupdate -radix hexadecimal /mac_lookup_tb/uut1/in_data
add wave -noupdate /mac_lookup_tb/uut1/in_last
add wave -noupdate /mac_lookup_tb/uut1/in_write
add wave -noupdate /mac_lookup_tb/uut1/out_pdst
add wave -noupdate /mac_lookup_tb/uut1/out_valid
add wave -noupdate /mac_lookup_tb/uut1/out_ready
add wave -noupdate /mac_lookup_tb/uut1/scrub_busy
add wave -noupdate /mac_lookup_tb/uut1/cfg_prmask
add wave -noupdate /mac_lookup_tb/uut1/error_change
add wave -noupdate /mac_lookup_tb/uut1/error_table
add wave -noupdate /mac_lookup_tb/uut1/got_packet
add wave -noupdate /mac_lookup_tb/uut1/got_result
add wave -noupdate -divider {UUT1 internals}
add wave -noupdate /mac_lookup_tb/uut1/uut/pkt_psrc
add wave -noupdate -radix hexadecimal /mac_lookup_tb/uut1/uut/pkt_dst_mac
add wave -noupdate /mac_lookup_tb/uut1/uut/pkt_dst_rdy
add wave -noupdate -radix hexadecimal /mac_lookup_tb/uut1/uut/pkt_src_mac
add wave -noupdate /mac_lookup_tb/uut1/uut/pkt_src_rdy
add wave -noupdate /mac_lookup_tb/uut1/uut/find_psrc
add wave -noupdate /mac_lookup_tb/uut1/uut/find_dst_idx
add wave -noupdate /mac_lookup_tb/uut1/uut/find_dst_all
add wave -noupdate /mac_lookup_tb/uut1/uut/find_dst_drp
add wave -noupdate /mac_lookup_tb/uut1/uut/find_dst_ok
add wave -noupdate /mac_lookup_tb/uut1/uut/find_dst_rdy
add wave -noupdate -radix hexadecimal /mac_lookup_tb/uut1/uut/find_src_mac
add wave -noupdate -radix hexadecimal /mac_lookup_tb/uut1/uut/find_src_idx
add wave -noupdate /mac_lookup_tb/uut1/uut/find_src_drp
add wave -noupdate /mac_lookup_tb/uut1/uut/find_src_ok
add wave -noupdate /mac_lookup_tb/uut1/uut/find_src_rdy
add wave -noupdate -radix unsigned /mac_lookup_tb/uut1/uut/cfg_pidx
add wave -noupdate -radix unsigned /mac_lookup_tb/uut1/uut/cfg_tidx
add wave -noupdate -radix unsigned /mac_lookup_tb/uut1/uut/cfg_tvec
add wave -noupdate -radix unsigned /mac_lookup_tb/uut1/uut/cfg_valid
add wave -noupdate -radix unsigned /mac_lookup_tb/uut1/uut/cfg_ready
add wave -noupdate -radix unsigned /mac_lookup_tb/uut1/uut/cfg_wren
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {97332 ns} 0}
configure wave -namecolwidth 265
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
WaveRestoreZoom {96748 ns} {100172 ns}
