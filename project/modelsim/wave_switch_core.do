# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test Control}
add wave -noupdate /switch_core_tb/test_phase
add wave -noupdate /switch_core_tb/test_run
add wave -noupdate /switch_core_tb/test_clr
add wave -noupdate /switch_core_tb/pkt_start
add wave -noupdate /switch_core_tb/pkt_sent
add wave -noupdate /switch_core_tb/pkt_expect
add wave -noupdate /switch_core_tb/pkt_rcvd
add wave -noupdate -radix unsigned /switch_core_tb/pkt_dst
add wave -noupdate -divider UUT
add wave -noupdate /switch_core_tb/uut/scrub_req
add wave -noupdate /switch_core_tb/uut/pktin_valid
add wave -noupdate /switch_core_tb/uut/pktin_ready
add wave -noupdate /switch_core_tb/uut/sched_select
add wave -noupdate /switch_core_tb/uut/pktout_hipri
add wave -noupdate /switch_core_tb/uut/pktout_write
add wave -noupdate /switch_core_tb/uut/pktout_pdst
add wave -noupdate -divider {Source 0}
add wave -noupdate /switch_core_tb/gen_ports(0)/u_src/p_src/pkt_rem
add wave -noupdate /switch_core_tb/gen_ports(0)/u_src/p_src/pkt_usr
add wave -noupdate -divider {Input 0}
add wave -noupdate -radix hexadecimal /switch_core_tb/uut/gen_input(0)/u_input/rx_data
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/rx_last
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/rx_write
add wave -noupdate -radix hexadecimal /switch_core_tb/uut/gen_input(0)/u_input/chk_data
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/chk_nlast
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/chk_write
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/chk_commit
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/chk_revert
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/chk_error
add wave -noupdate -radix hexadecimal /switch_core_tb/uut/gen_input(0)/u_input/out_data
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/out_nlast
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/out_last
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/out_valid
add wave -noupdate /switch_core_tb/uut/gen_input(0)/u_input/out_ready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {199695 ns} 0}
configure wave -namecolwidth 322
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
WaveRestoreZoom {199609 ns} {200021 ns}
