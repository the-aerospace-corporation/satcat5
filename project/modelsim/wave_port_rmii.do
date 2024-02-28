# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /port_rmii_tb/reset_p
add wave -noupdate -divider A2B
add wave -noupdate /port_rmii_tb/a2b_data
add wave -noupdate /port_rmii_tb/a2b_en
add wave -noupdate /port_rmii_tb/a2b_er
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_rmii_tb/rxdata_a.clk {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_a.data {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_a.last {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_a.write {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_a.rxerr {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_a.reset_p {-height 15 -radix hexadecimal}} /port_rmii_tb/rxdata_a
add wave -noupdate -radix hexadecimal /port_rmii_tb/u_src_b2a/ref_data
add wave -noupdate /port_rmii_tb/u_src_b2a/ref_last
add wave -noupdate /port_rmii_tb/u_src_b2a/rcvd_pkt
add wave -noupdate -divider B2A
add wave -noupdate /port_rmii_tb/b2a_data
add wave -noupdate /port_rmii_tb/b2a_en
add wave -noupdate /port_rmii_tb/b2a_er
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_rmii_tb/rxdata_b.clk {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_b.data {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_b.last {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_b.write {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_b.rxerr {-height 15 -radix hexadecimal} /port_rmii_tb/rxdata_b.reset_p {-height 15 -radix hexadecimal}} /port_rmii_tb/rxdata_b
add wave -noupdate -radix hexadecimal /port_rmii_tb/u_src_a2b/ref_data
add wave -noupdate /port_rmii_tb/u_src_a2b/ref_last
add wave -noupdate /port_rmii_tb/u_src_a2b/rcvd_pkt
add wave -noupdate -divider {Internals A}
add wave -noupdate /port_rmii_tb/uut_a/u_amble_rx/raw_lock
add wave -noupdate /port_rmii_tb/uut_a/u_amble_rx/raw_cken
add wave -noupdate -radix hexadecimal /port_rmii_tb/uut_a/u_amble_rx/raw_data
add wave -noupdate /port_rmii_tb/uut_a/u_amble_rx/raw_dv
add wave -noupdate /port_rmii_tb/uut_a/u_amble_rx/raw_err
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {10537571593 ps} 0}
configure wave -namecolwidth 293
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
WaveRestoreZoom {5432005453 ps} {33398315503 ps}
