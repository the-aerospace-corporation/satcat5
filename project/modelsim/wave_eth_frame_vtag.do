# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider UUT1
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut1/in_vtag
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut1/in_data
add wave -noupdate /eth_frame_vtag_tb/uut1/in_nlast
add wave -noupdate /eth_frame_vtag_tb/uut1/in_valid
add wave -noupdate /eth_frame_vtag_tb/uut1/in_ready
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut1/ref_data
add wave -noupdate /eth_frame_vtag_tb/uut1/ref_nlast
add wave -noupdate /eth_frame_vtag_tb/uut1/ref_valid
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut1/out_data
add wave -noupdate /eth_frame_vtag_tb/uut1/out_nlast
add wave -noupdate /eth_frame_vtag_tb/uut1/out_valid
add wave -noupdate /eth_frame_vtag_tb/uut1/out_ready
add wave -noupdate -divider {UUT1 Internals}
add wave -noupdate /eth_frame_vtag_tb/uut1/uut/in_write
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut1/uut/in_sreg
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut1/uut/mod_vtag
add wave -noupdate /eth_frame_vtag_tb/uut1/uut/tag_wcount
add wave -noupdate /eth_frame_vtag_tb/uut1/uut/tag_policy
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut1/uut/tag_data
add wave -noupdate /eth_frame_vtag_tb/uut1/uut/tag_nlast
add wave -noupdate /eth_frame_vtag_tb/uut1/uut/tag_novr
add wave -noupdate /eth_frame_vtag_tb/uut1/uut/tag_busy
add wave -noupdate /eth_frame_vtag_tb/uut1/uut/tag_valid
add wave -noupdate /eth_frame_vtag_tb/uut1/uut/tag_ready
add wave -noupdate /eth_frame_vtag_tb/uut1/uut/tag_next
add wave -noupdate /eth_frame_vtag_tb/uut1/uut/cfg_policy
add wave -noupdate -divider UUT2
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut2/in_vtag
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut2/in_data
add wave -noupdate /eth_frame_vtag_tb/uut2/in_nlast
add wave -noupdate /eth_frame_vtag_tb/uut2/in_valid
add wave -noupdate /eth_frame_vtag_tb/uut2/in_ready
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut2/ref_data
add wave -noupdate /eth_frame_vtag_tb/uut2/ref_nlast
add wave -noupdate /eth_frame_vtag_tb/uut2/ref_valid
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut2/out_data
add wave -noupdate /eth_frame_vtag_tb/uut2/out_nlast
add wave -noupdate /eth_frame_vtag_tb/uut2/out_valid
add wave -noupdate /eth_frame_vtag_tb/uut2/out_ready
add wave -noupdate -divider {UUT2 Internals}
add wave -noupdate /eth_frame_vtag_tb/uut2/uut/in_write
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut2/uut/in_sreg
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut2/uut/mod_vtag
add wave -noupdate /eth_frame_vtag_tb/uut2/uut/tag_wcount
add wave -noupdate /eth_frame_vtag_tb/uut2/uut/tag_policy
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut2/uut/tag_data
add wave -noupdate /eth_frame_vtag_tb/uut2/uut/tag_nlast
add wave -noupdate /eth_frame_vtag_tb/uut2/uut/tag_novr
add wave -noupdate /eth_frame_vtag_tb/uut2/uut/tag_busy
add wave -noupdate /eth_frame_vtag_tb/uut2/uut/tag_valid
add wave -noupdate /eth_frame_vtag_tb/uut2/uut/tag_ready
add wave -noupdate /eth_frame_vtag_tb/uut2/uut/tag_next
add wave -noupdate /eth_frame_vtag_tb/uut2/uut/cfg_policy
add wave -noupdate -divider UUT3
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut3/in_vtag
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut3/in_data
add wave -noupdate /eth_frame_vtag_tb/uut3/in_nlast
add wave -noupdate /eth_frame_vtag_tb/uut3/in_valid
add wave -noupdate /eth_frame_vtag_tb/uut3/in_ready
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut3/ref_data
add wave -noupdate /eth_frame_vtag_tb/uut3/ref_nlast
add wave -noupdate /eth_frame_vtag_tb/uut3/ref_valid
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut3/out_data
add wave -noupdate /eth_frame_vtag_tb/uut3/out_nlast
add wave -noupdate /eth_frame_vtag_tb/uut3/out_valid
add wave -noupdate /eth_frame_vtag_tb/uut3/out_ready
add wave -noupdate -divider {UUT3 Internals}
add wave -noupdate /eth_frame_vtag_tb/uut3/uut/in_write
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut3/uut/in_sreg
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut3/uut/mod_vtag
add wave -noupdate /eth_frame_vtag_tb/uut3/uut/tag_wcount
add wave -noupdate /eth_frame_vtag_tb/uut3/uut/tag_policy
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut3/uut/tag_data
add wave -noupdate /eth_frame_vtag_tb/uut3/uut/tag_nlast
add wave -noupdate /eth_frame_vtag_tb/uut3/uut/tag_novr
add wave -noupdate /eth_frame_vtag_tb/uut3/uut/tag_busy
add wave -noupdate /eth_frame_vtag_tb/uut3/uut/tag_valid
add wave -noupdate /eth_frame_vtag_tb/uut3/uut/tag_ready
add wave -noupdate /eth_frame_vtag_tb/uut3/uut/tag_next
add wave -noupdate /eth_frame_vtag_tb/uut3/uut/cfg_policy
add wave -noupdate -divider UUT5
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut5/in_data
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut5/in_vtag
add wave -noupdate /eth_frame_vtag_tb/uut5/in_valid
add wave -noupdate /eth_frame_vtag_tb/uut5/in_ready
add wave -noupdate /eth_frame_vtag_tb/uut5/in_nlast
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut5/ref_data
add wave -noupdate /eth_frame_vtag_tb/uut5/ref_nlast
add wave -noupdate /eth_frame_vtag_tb/uut5/ref_valid
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut5/out_data
add wave -noupdate /eth_frame_vtag_tb/uut5/out_nlast
add wave -noupdate /eth_frame_vtag_tb/uut5/out_valid
add wave -noupdate /eth_frame_vtag_tb/uut5/out_ready
add wave -noupdate -divider {UUT5 Internals}
add wave -noupdate /eth_frame_vtag_tb/uut5/uut/in_write
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut5/uut/in_sreg
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut5/uut/mod_vtag
add wave -noupdate /eth_frame_vtag_tb/uut5/uut/tag_wcount
add wave -noupdate /eth_frame_vtag_tb/uut5/uut/tag_policy
add wave -noupdate -radix hexadecimal /eth_frame_vtag_tb/uut5/uut/tag_data
add wave -noupdate /eth_frame_vtag_tb/uut5/uut/tag_nlast
add wave -noupdate /eth_frame_vtag_tb/uut5/uut/tag_novr
add wave -noupdate /eth_frame_vtag_tb/uut5/uut/tag_busy
add wave -noupdate /eth_frame_vtag_tb/uut5/uut/tag_valid
add wave -noupdate /eth_frame_vtag_tb/uut5/uut/tag_ready
add wave -noupdate /eth_frame_vtag_tb/uut5/uut/tag_next
add wave -noupdate /eth_frame_vtag_tb/uut5/uut/cfg_policy
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {37034725 ps} 0}
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
WaveRestoreZoom {31116011 ps} {40467579 ps}
