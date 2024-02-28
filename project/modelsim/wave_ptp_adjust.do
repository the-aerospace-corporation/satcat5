# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/in_meta
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/in_data
add wave -noupdate /ptp_adjust_tb/uut0/in_nlast
add wave -noupdate /ptp_adjust_tb/uut0/in_valid
add wave -noupdate /ptp_adjust_tb/uut0/in_ready
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/out_meta
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/out_data
add wave -noupdate /ptp_adjust_tb/uut0/out_nlast
add wave -noupdate /ptp_adjust_tb/uut0/out_valid
add wave -noupdate /ptp_adjust_tb/uut0/out_ready
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/out_meta_v
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/frm_pmask
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/frm_pmode
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/frm_tstamp
add wave -noupdate /ptp_adjust_tb/uut0/frm_valid
add wave -noupdate /ptp_adjust_tb/uut0/frm_ready
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/ref_data
add wave -noupdate /ptp_adjust_tb/uut0/ref_nlast
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/ref_meta_v
add wave -noupdate /ptp_adjust_tb/uut0/ref_pkvalid
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/ref_pkmeta
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/frm_pkmeta
add wave -noupdate /ptp_adjust_tb/uut0/uut/gen_mixed1/blk_mixed/ptp_write
add wave -noupdate /ptp_adjust_tb/uut0/uut/gen_mixed1/blk_mixed/ptp_commit
add wave -noupdate /ptp_adjust_tb/uut0/uut/gen_mixed1/blk_mixed/ptp_revert
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/uut/gen_mixed1/blk_mixed/fifo_data
add wave -noupdate /ptp_adjust_tb/uut0/uut/gen_mixed1/blk_mixed/fifo_nlast
add wave -noupdate /ptp_adjust_tb/uut0/uut/gen_mixed1/blk_mixed/fifo_valid
add wave -noupdate /ptp_adjust_tb/uut0/uut/gen_mixed1/blk_mixed/fifo_ready
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/uut/mix_data
add wave -noupdate /ptp_adjust_tb/uut0/uut/mix_valid
add wave -noupdate /ptp_adjust_tb/uut0/uut/mix_ready
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/uut/ptp_data
add wave -noupdate /ptp_adjust_tb/uut0/uut/ptp_valid
add wave -noupdate /ptp_adjust_tb/uut0/uut/ptp_ready
add wave -noupdate /ptp_adjust_tb/uut0/uut/ptp_clone
add wave -noupdate /ptp_adjust_tb/uut0/uut/ptp_follow
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/uut/mod_data
add wave -noupdate /ptp_adjust_tb/uut0/uut/mod_valid
add wave -noupdate /ptp_adjust_tb/uut0/uut/mod_ready
add wave -noupdate /ptp_adjust_tb/uut0/uut/ptp_is_udp
add wave -noupdate /ptp_adjust_tb/uut0/uut/ptp_is_adj
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/uut/ptp_ip_ihl
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/uut/ptp_msg_sdo
add wave -noupdate -radix hexadecimal /ptp_adjust_tb/uut0/uut/ptp_msg_typ
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1311884 ns} 0}
configure wave -namecolwidth 381
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
WaveRestoreZoom {1761296 ns} {1762080 ns}
