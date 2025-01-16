# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider UUT0
add wave -noupdate /router2_offload_tb/uut0/test_index
add wave -noupdate /router2_offload_tb/uut0/test_mode
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/in_data
add wave -noupdate /router2_offload_tb/uut0/in_nlast
add wave -noupdate /router2_offload_tb/uut0/in_valid
add wave -noupdate /router2_offload_tb/uut0/in_ready
add wave -noupdate /router2_offload_tb/uut0/in_pdst
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/out_data
add wave -noupdate /router2_offload_tb/uut0/out_nlast
add wave -noupdate -radix binary /router2_offload_tb/uut0/out_pdst
add wave -noupdate /router2_offload_tb/uut0/out_valid
add wave -noupdate /router2_offload_tb/uut0/out_ready
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/ref_data
add wave -noupdate /router2_offload_tb/uut0/ref_nlast
add wave -noupdate -radix binary /router2_offload_tb/uut0/ref_pdst
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/router2_offload_tb/uut0/cfg_cmd.clk {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_cmd.sysaddr {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_cmd.devaddr {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_cmd.regaddr {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_cmd.wdata {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_cmd.wstrb {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_cmd.wrcmd {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_cmd.rdcmd {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_cmd.reset_p {-height 15 -radix hexadecimal}} /router2_offload_tb/uut0/cfg_cmd
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/router2_offload_tb/uut0/cfg_ack.rdata {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_ack.rdack {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_ack.rderr {-height 15 -radix hexadecimal} /router2_offload_tb/uut0/cfg_ack.irq {-height 15 -radix hexadecimal}} /router2_offload_tb/uut0/cfg_ack
add wave -noupdate -divider {UUT0 Internals}
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/buf_data
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/buf_nlast
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/buf_valid
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/buf_ready
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/buf_offwr
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/buf_commit
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/fwd_data
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/fwd_nlast
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/fwd_valid
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/fwd_ready
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/aux_data
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/aux_pdst
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/aux_nlast
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/aux_valid
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut0/uut/aux_ready
add wave -noupdate -divider UUT1
add wave -noupdate /router2_offload_tb/uut1/test_index
add wave -noupdate /router2_offload_tb/uut1/test_mode
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/in_data
add wave -noupdate /router2_offload_tb/uut1/in_nlast
add wave -noupdate /router2_offload_tb/uut1/in_valid
add wave -noupdate /router2_offload_tb/uut1/in_ready
add wave -noupdate /router2_offload_tb/uut1/in_pdst
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/out_data
add wave -noupdate /router2_offload_tb/uut1/out_nlast
add wave -noupdate /router2_offload_tb/uut1/out_valid
add wave -noupdate /router2_offload_tb/uut1/out_ready
add wave -noupdate -radix binary /router2_offload_tb/uut1/out_pdst
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/ref_data
add wave -noupdate /router2_offload_tb/uut1/ref_nlast
add wave -noupdate -radix binary /router2_offload_tb/uut1/ref_pdst
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/cfg_cmd
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/cfg_ack
add wave -noupdate -divider {UUT1 Internals}
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/buf_data
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/buf_nlast
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/buf_valid
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/buf_ready
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/buf_offwr
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/buf_commit
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/fwd_data
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/fwd_nlast
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/fwd_valid
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/fwd_ready
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/aux_data
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/aux_pdst
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/aux_meta
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/aux_nlast
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/aux_valid
add wave -noupdate -radix hexadecimal /router2_offload_tb/uut1/uut/aux_ready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1754538 ps} 0}
configure wave -namecolwidth 307
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
WaveRestoreZoom {1512563 ps} {2927187 ps}
