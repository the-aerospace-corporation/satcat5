# Copyright 2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Top Level}
add wave -noupdate /cobs_encoder_tb/test_idx
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/in_data
add wave -noupdate /cobs_encoder_tb/in_last
add wave -noupdate /cobs_encoder_tb/in_valid
add wave -noupdate /cobs_encoder_tb/in_ready
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/mid_data
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/mid_ref
add wave -noupdate /cobs_encoder_tb/mid_last
add wave -noupdate /cobs_encoder_tb/mid_valid
add wave -noupdate /cobs_encoder_tb/mid_ready
add wave -noupdate /cobs_encoder_tb/mid_write
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/out_data
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/out_ref
add wave -noupdate /cobs_encoder_tb/out_last
add wave -noupdate /cobs_encoder_tb/out_write
add wave -noupdate -divider Encoder
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/u_enc/look_count
add wave -noupdate /cobs_encoder_tb/u_enc/look_meta
add wave -noupdate /cobs_encoder_tb/u_enc/look_incr
add wave -noupdate /cobs_encoder_tb/u_enc/look_write
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/u_enc/dly_data
add wave -noupdate /cobs_encoder_tb/u_enc/dly_last
add wave -noupdate /cobs_encoder_tb/u_enc/dly_valid
add wave -noupdate /cobs_encoder_tb/u_enc/dly_read
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/u_enc/len_word
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/u_enc/len_count
add wave -noupdate /cobs_encoder_tb/u_enc/len_meta
add wave -noupdate /cobs_encoder_tb/u_enc/len_valid
add wave -noupdate /cobs_encoder_tb/u_enc/len_read
add wave -noupdate /cobs_encoder_tb/u_enc/enc_state
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/u_enc/enc_count
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/u_enc/enc_data
add wave -noupdate /cobs_encoder_tb/u_enc/enc_valid
add wave -noupdate /cobs_encoder_tb/u_enc/enc_next
add wave -noupdate -divider Decoder
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/u_dec/dec_data
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/u_dec/dec_rem
add wave -noupdate /cobs_encoder_tb/u_dec/dec_type
add wave -noupdate /cobs_encoder_tb/u_dec/dec_valid
add wave -noupdate /cobs_encoder_tb/u_dec/dec_eof
add wave -noupdate /cobs_encoder_tb/u_dec/dec_err
add wave -noupdate /cobs_encoder_tb/u_dec/dec_write
add wave -noupdate -radix hexadecimal /cobs_encoder_tb/u_dec/fin_data
add wave -noupdate /cobs_encoder_tb/u_dec/fin_write
add wave -noupdate /cobs_encoder_tb/u_dec/fin_result
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {39879409 ps} 0}
configure wave -namecolwidth 278
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
WaveRestoreZoom {39875313 ps} {40006563 ps}
