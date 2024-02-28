# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test Status}
add wave -noupdate /sgmii_data_sync_tb/test_index
add wave -noupdate /sgmii_data_sync_tb/test_reset
add wave -noupdate /sgmii_data_sync_tb/test_df_ppm
add wave -noupdate /sgmii_data_sync_tb/test_jitter
add wave -noupdate /sgmii_data_sync_tb/out_locked
add wave -noupdate /sgmii_data_sync_tb/ref_locked
add wave -noupdate /sgmii_data_sync_tb/in_count
add wave -noupdate -divider {Reference lock state}
add wave -noupdate /sgmii_data_sync_tb/out_error
add wave -noupdate /sgmii_data_sync_tb/ref_errors
add wave -noupdate /sgmii_data_sync_tb/ref_checked
add wave -noupdate -divider {Input and Output Streams}
add wave -noupdate -radix hexadecimal /sgmii_data_sync_tb/in_data
add wave -noupdate /sgmii_data_sync_tb/in_next
add wave -noupdate -radix hexadecimal /sgmii_data_sync_tb/ref_data
add wave -noupdate -radix hexadecimal /sgmii_data_sync_tb/out_data
add wave -noupdate /sgmii_data_sync_tb/out_next
add wave -noupdate -divider {Alignment stats}
add wave -noupdate -expand /sgmii_data_sync_tb/aux_stats
add wave -noupdate -divider {UUT Internals}
add wave -noupdate /sgmii_data_sync_tb/uut/bias_early
add wave -noupdate /sgmii_data_sync_tb/uut/det_early2
add wave -noupdate /sgmii_data_sync_tb/uut/det_early1
add wave -noupdate /sgmii_data_sync_tb/uut/det_ontime
add wave -noupdate /sgmii_data_sync_tb/uut/det_late1
add wave -noupdate /sgmii_data_sync_tb/uut/det_late2
add wave -noupdate /sgmii_data_sync_tb/uut/det_next
add wave -noupdate -format Analog-Step -height 74 -max 1023.0000000000001 /sgmii_data_sync_tb/uut/p_track/score_lock
add wave -noupdate -format Analog-Step -height 74 -max 408.99999999999994 -min -404.0 /sgmii_data_sync_tb/uut/score_track
add wave -noupdate /sgmii_data_sync_tb/uut/trk_locked
add wave -noupdate /sgmii_data_sync_tb/uut/trk_early
add wave -noupdate /sgmii_data_sync_tb/uut/trk_late
add wave -noupdate /sgmii_data_sync_tb/uut/trk_ready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {688600608 ps} 0}
configure wave -namecolwidth 273
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
WaveRestoreZoom {49999323445 ps} {50000035609 ps}
