# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test Status}
add wave -noupdate /eth_all8b10b_tb/test_idx
add wave -noupdate /eth_all8b10b_tb/test_shift
add wave -noupdate /eth_all8b10b_tb/test_rate
add wave -noupdate /eth_all8b10b_tb/test_txen
add wave -noupdate -divider {Input stream}
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/in_data
add wave -noupdate /eth_all8b10b_tb/in_dv
add wave -noupdate /eth_all8b10b_tb/in_cken
add wave -noupdate -divider {Output and reference}
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/out_port
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/ref_data
add wave -noupdate /eth_all8b10b_tb/ref_last
add wave -noupdate -divider {Configuration word}
add wave -noupdate /eth_all8b10b_tb/cfg_txen
add wave -noupdate /eth_all8b10b_tb/cfg_rcvd
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/cfg_txdata
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/cfg_rxdata
add wave -noupdate -divider {Encoder internals}
add wave -noupdate /eth_all8b10b_tb/uut_enc/strm_state
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/uut_enc/strm_data
add wave -noupdate /eth_all8b10b_tb/uut_enc/strm_ctrl
add wave -noupdate /eth_all8b10b_tb/uut_enc/strm_even
add wave -noupdate /eth_all8b10b_tb/uut_enc/strm_cfgct
add wave -noupdate /eth_all8b10b_tb/uut_enc/strm_cken
add wave -noupdate -divider {Decoder internals}
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/uut_dec/align_data
add wave -noupdate /eth_all8b10b_tb/uut_dec/align_cken
add wave -noupdate /eth_all8b10b_tb/uut_dec/align_lock
add wave -noupdate /eth_all8b10b_tb/uut_dec/p_align/align_bit
add wave -noupdate /eth_all8b10b_tb/uut_dec/p_align/count_comma
add wave -noupdate /eth_all8b10b_tb/uut_dec/p_align/count_other
add wave -noupdate /eth_all8b10b_tb/uut_dec/p_meta/cfg_tok
add wave -noupdate /eth_all8b10b_tb/uut_dec/p_meta/cfg_ctr
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {99389426 ps} 0}
configure wave -namecolwidth 360
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
WaveRestoreZoom {98521344 ps} {100077824 ps}
