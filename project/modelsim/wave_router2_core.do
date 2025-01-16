# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /router2_core_tb/test_phase
add wave -noupdate /router2_core_tb/test_clr
add wave -noupdate /router2_core_tb/test_run
add wave -noupdate /router2_core_tb/test_regaddr
add wave -noupdate -radix hexadecimal /router2_core_tb/test_wdata
add wave -noupdate /router2_core_tb/test_wrcmd
add wave -noupdate /router2_core_tb/test_rdcmd
add wave -noupdate -radix unsigned -expand -subitemconfig {/router2_core_tb/pkt_dst(4) {-radix unsigned} /router2_core_tb/pkt_dst(3) {-radix unsigned} /router2_core_tb/pkt_dst(2) {-radix unsigned} /router2_core_tb/pkt_dst(1) {-radix unsigned} /router2_core_tb/pkt_dst(0) {-radix unsigned}} /router2_core_tb/pkt_dst
add wave -noupdate /router2_core_tb/pkt_expect
add wave -noupdate /router2_core_tb/pkt_rcvd
add wave -noupdate /router2_core_tb/pkt_sent
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/router2_core_tb/prx_data(4) {-height 15 -radix hexadecimal} /router2_core_tb/prx_data(3) {-height 15 -radix hexadecimal} /router2_core_tb/prx_data(2) {-height 15 -radix hexadecimal} /router2_core_tb/prx_data(1) {-height 15 -radix hexadecimal} /router2_core_tb/prx_data(0) {-height 15 -radix hexadecimal}} /router2_core_tb/prx_data
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/router2_core_tb/ptx_data(4) {-height 15 -radix hexadecimal} /router2_core_tb/ptx_data(3) {-height 15 -radix hexadecimal} /router2_core_tb/ptx_data(2) {-height 15 -radix hexadecimal} /router2_core_tb/ptx_data(1) {-height 15 -radix hexadecimal} /router2_core_tb/ptx_data(0) {-height 15 -radix hexadecimal}} /router2_core_tb/ptx_data
add wave -noupdate -radix hexadecimal /router2_core_tb/ptx_ctrl
add wave -noupdate /router2_core_tb/uut/u_router/reset_p
add wave -noupdate /router2_core_tb/uut/u_router/in_psrc
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/in_data
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/in_meta
add wave -noupdate /router2_core_tb/uut/u_router/in_nlast
add wave -noupdate /router2_core_tb/uut/u_router/in_valid
add wave -noupdate /router2_core_tb/uut/u_router/in_ready
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/gate_data
add wave -noupdate /router2_core_tb/uut/u_router/gate_nlast
add wave -noupdate /router2_core_tb/uut/u_router/gate_valid
add wave -noupdate /router2_core_tb/uut/u_router/gate_ready
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/gate_dstmac
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/gate_srcmac
add wave -noupdate /router2_core_tb/uut/u_router/gate_pdst
add wave -noupdate /router2_core_tb/uut/u_router/gate_psrc
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/gate_meta
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/fwd_data
add wave -noupdate /router2_core_tb/uut/u_router/fwd_nlast
add wave -noupdate /router2_core_tb/uut/u_router/fwd_valid
add wave -noupdate /router2_core_tb/uut/u_router/fwd_ready
add wave -noupdate /router2_core_tb/uut/u_router/fwd_pdst0
add wave -noupdate /router2_core_tb/uut/u_router/fwd_psrc
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/fwd_meta
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/ecn_data
add wave -noupdate /router2_core_tb/uut/u_router/ecn_nlast
add wave -noupdate /router2_core_tb/uut/u_router/ecn_drop
add wave -noupdate /router2_core_tb/uut/u_router/ecn_pdst
add wave -noupdate /router2_core_tb/uut/u_router/ecn_pmod
add wave -noupdate /router2_core_tb/uut/u_router/ecn_write
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/chk_data
add wave -noupdate /router2_core_tb/uut/u_router/chk_nlast
add wave -noupdate /router2_core_tb/uut/u_router/chk_write
add wave -noupdate /router2_core_tb/uut/u_router/chk_pdst
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/reset_p
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/buf_data
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/buf_nlast
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/buf_valid
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/buf_ready
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/buf_dstmac
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/buf_srcmac
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/buf_offwr
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/buf_commit
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/buf_psrc
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/buf_vtag
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/buf_mvec
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/fwd_data
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/fwd_mvec
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/fwd_nlast
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/fwd_valid
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/fwd_ready
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/aux_data
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/aux_pdst
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/aux_vtag
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/aux_meta
add wave -noupdate -radix hexadecimal /router2_core_tb/uut/u_router/u_offload/aux_mvec
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/aux_nlast
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/aux_valid
add wave -noupdate /router2_core_tb/uut/u_router/u_offload/aux_ready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {21255275 ps} 0}
configure wave -namecolwidth 348
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
WaveRestoreZoom {21148188 ps} {21455808 ps}
