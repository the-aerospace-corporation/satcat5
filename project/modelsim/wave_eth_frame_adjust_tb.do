# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test status}
add wave -noupdate /eth_frame_adjust_tb/frm_idx
add wave -noupdate /eth_frame_adjust_tb/frm_ok
add wave -noupdate /eth_frame_adjust_tb/frm_err
add wave -noupdate /eth_frame_adjust_tb/in_rate
add wave -noupdate /eth_frame_adjust_tb/out_rate
add wave -noupdate /eth_frame_adjust_tb/pkt_len
add wave -noupdate -divider {Input stream}
add wave -noupdate -radix hexadecimal /eth_frame_adjust_tb/in_data
add wave -noupdate /eth_frame_adjust_tb/in_last
add wave -noupdate /eth_frame_adjust_tb/in_valid
add wave -noupdate /eth_frame_adjust_tb/in_ready
add wave -noupdate /eth_frame_adjust_tb/in_valid_raw
add wave -noupdate /eth_frame_adjust_tb/in_valid_ovr
add wave -noupdate /eth_frame_adjust_tb/in_last_ovr
add wave -noupdate -divider {Output stream}
add wave -noupdate -radix hexadecimal /eth_frame_adjust_tb/ref_data
add wave -noupdate /eth_frame_adjust_tb/ref_last
add wave -noupdate -radix hexadecimal /eth_frame_adjust_tb/out_data
add wave -noupdate /eth_frame_adjust_tb/out_last
add wave -noupdate /eth_frame_adjust_tb/out_valid
add wave -noupdate /eth_frame_adjust_tb/out_ready
add wave -noupdate /eth_frame_adjust_tb/out_write
add wave -noupdate -divider {Output checking}
add wave -noupdate /eth_frame_adjust_tb/fifo_wr
add wave -noupdate /eth_frame_adjust_tb/fifo_rd
add wave -noupdate /eth_frame_adjust_tb/p_check_dat/contig_cnt
add wave -noupdate /eth_frame_adjust_tb/p_check_dat/contig_req
add wave -noupdate /eth_frame_adjust_tb/p_check_dat/ref_end
add wave -noupdate -divider {UUT internals}
add wave -noupdate -radix hexadecimal /eth_frame_adjust_tb/uut/frm_data
add wave -noupdate /eth_frame_adjust_tb/uut/frm_last
add wave -noupdate /eth_frame_adjust_tb/uut/frm_valid
add wave -noupdate /eth_frame_adjust_tb/uut/frm_ready
add wave -noupdate /eth_frame_adjust_tb/uut/p_pad/bcount
add wave -noupdate /eth_frame_adjust_tb/uut/pad_ovr
add wave -noupdate -radix hexadecimal /eth_frame_adjust_tb/uut/pad_data
add wave -noupdate /eth_frame_adjust_tb/uut/pad_last
add wave -noupdate /eth_frame_adjust_tb/uut/pad_valid
add wave -noupdate /eth_frame_adjust_tb/uut/pad_ready
add wave -noupdate /eth_frame_adjust_tb/uut/p_crc/bcount
add wave -noupdate /eth_frame_adjust_tb/uut/fcs_ovr
add wave -noupdate -radix hexadecimal /eth_frame_adjust_tb/uut/fcs_data
add wave -noupdate /eth_frame_adjust_tb/uut/fcs_last
add wave -noupdate /eth_frame_adjust_tb/uut/fcs_valid
add wave -noupdate /eth_frame_adjust_tb/uut/fcs_ready
add wave -noupdate -divider {CRC register}
add wave -noupdate -radix hexadecimal /eth_frame_adjust_tb/u_src/p_src/pkt_crc
add wave -noupdate -radix hexadecimal /eth_frame_adjust_tb/uut/fcs_crc32
add wave -noupdate -radix hexadecimal /eth_frame_adjust_tb/u_check_fcs/crc_sreg
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {686895000 ps} 0}
configure wave -namecolwidth 332
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
WaveRestoreZoom {0 ps} {2310 us}
