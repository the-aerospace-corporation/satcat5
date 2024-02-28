# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Stream A2B}
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_rgmii_tb/txdata_a.data {-height 15 -radix hexadecimal} /port_rgmii_tb/txdata_a.last {-height 15 -radix hexadecimal} /port_rgmii_tb/txdata_a.valid {-height 15 -radix hexadecimal}} /port_rgmii_tb/txdata_a
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_rgmii_tb/rgmii_a2b.clk {-height 15 -radix hexadecimal} /port_rgmii_tb/rgmii_a2b.data {-height 15 -radix hexadecimal} /port_rgmii_tb/rgmii_a2b.ctl {-height 15 -radix hexadecimal}} /port_rgmii_tb/rgmii_a2b
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_rgmii_tb/rxdata_b.clk {-height 15 -radix hexadecimal} /port_rgmii_tb/rxdata_b.data {-height 15 -radix hexadecimal} /port_rgmii_tb/rxdata_b.last {-height 15 -radix hexadecimal} /port_rgmii_tb/rxdata_b.write {-height 15 -radix hexadecimal} /port_rgmii_tb/rxdata_b.rxerr {-height 15 -radix hexadecimal} /port_rgmii_tb/rxdata_b.reset_p {-height 15 -radix hexadecimal}} /port_rgmii_tb/rxdata_b
add wave -noupdate -radix hexadecimal /port_rgmii_tb/u_src_a2b/ref_data
add wave -noupdate /port_rgmii_tb/u_src_a2b/ref_last
add wave -noupdate -divider {Stream B2A}
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_rgmii_tb/txdata_b.data {-height 15 -radix hexadecimal} /port_rgmii_tb/txdata_b.last {-height 15 -radix hexadecimal} /port_rgmii_tb/txdata_b.valid {-height 15 -radix hexadecimal}} /port_rgmii_tb/txdata_b
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_rgmii_tb/rgmii_b2a.clk {-height 15 -radix hexadecimal} /port_rgmii_tb/rgmii_b2a.data {-height 15 -radix hexadecimal} /port_rgmii_tb/rgmii_b2a.ctl {-height 15 -radix hexadecimal}} /port_rgmii_tb/rgmii_b2a
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_rgmii_tb/rxdata_a.clk {-height 15 -radix hexadecimal} /port_rgmii_tb/rxdata_a.data {-height 15 -radix hexadecimal} /port_rgmii_tb/rxdata_a.last {-height 15 -radix hexadecimal} /port_rgmii_tb/rxdata_a.write {-height 15 -radix hexadecimal} /port_rgmii_tb/rxdata_a.rxerr {-height 15 -radix hexadecimal} /port_rgmii_tb/rxdata_a.reset_p {-height 15 -radix hexadecimal}} /port_rgmii_tb/rxdata_a
add wave -noupdate -radix hexadecimal /port_rgmii_tb/u_src_b2a/ref_data
add wave -noupdate /port_rgmii_tb/u_src_b2a/ref_last
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {71569507 ps} 0}
configure wave -namecolwidth 358
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
WaveRestoreZoom {0 ps} {1260 us}
