# Copyright 2019 The Aerospace Corporation
#
# This file is part of SatCat5.
#
# SatCat5 is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# SatCat5 is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Packet counts}
add wave -noupdate /port_inline_status_tb/test_count_rst
add wave -noupdate /port_inline_status_tb/eg_count_pri
add wave -noupdate /port_inline_status_tb/eg_count_aux
add wave -noupdate /port_inline_status_tb/ig_count_pri
add wave -noupdate /port_inline_status_tb/ig_count_aux
add wave -noupdate -divider {Egress streams}
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_inline_status_tb/lcl_tx_data.data {-height 15 -radix hexadecimal} /port_inline_status_tb/lcl_tx_data.last {-height 15 -radix hexadecimal} /port_inline_status_tb/lcl_tx_data.valid {-height 15 -radix hexadecimal}} /port_inline_status_tb/lcl_tx_data
add wave -noupdate -expand /port_inline_status_tb/lcl_tx_ctrl
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_inline_status_tb/net_tx_data.data {-height 15 -radix hexadecimal} /port_inline_status_tb/net_tx_data.last {-height 15 -radix hexadecimal} /port_inline_status_tb/net_tx_data.valid {-height 15 -radix hexadecimal}} /port_inline_status_tb/net_tx_data
add wave -noupdate -expand /port_inline_status_tb/net_tx_ctrl
add wave -noupdate -radix hexadecimal /port_inline_status_tb/out_eg_data
add wave -noupdate /port_inline_status_tb/out_eg_write
add wave -noupdate /port_inline_status_tb/out_eg_commit
add wave -noupdate /port_inline_status_tb/out_eg_revert
add wave -noupdate -divider {Ingress streams}
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_inline_status_tb/net_rx_data.clk {-height 15 -radix hexadecimal} /port_inline_status_tb/net_rx_data.data {-height 15 -radix hexadecimal} /port_inline_status_tb/net_rx_data.last {-height 15 -radix hexadecimal} /port_inline_status_tb/net_rx_data.write {-height 15 -radix hexadecimal} /port_inline_status_tb/net_rx_data.rxerr {-height 15 -radix hexadecimal} /port_inline_status_tb/net_rx_data.reset_p {-height 15 -radix hexadecimal}} /port_inline_status_tb/net_rx_data
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/port_inline_status_tb/lcl_rx_data.clk {-height 15 -radix hexadecimal} /port_inline_status_tb/lcl_rx_data.data {-height 15 -radix hexadecimal} /port_inline_status_tb/lcl_rx_data.last {-height 15 -radix hexadecimal} /port_inline_status_tb/lcl_rx_data.write {-height 15 -radix hexadecimal} /port_inline_status_tb/lcl_rx_data.rxerr {-height 15 -radix hexadecimal} /port_inline_status_tb/lcl_rx_data.reset_p {-height 15 -radix hexadecimal}} /port_inline_status_tb/lcl_rx_data
add wave -noupdate -radix hexadecimal /port_inline_status_tb/out_ig_data
add wave -noupdate /port_inline_status_tb/out_ig_write
add wave -noupdate /port_inline_status_tb/out_ig_commit
add wave -noupdate /port_inline_status_tb/out_ig_revert
add wave -noupdate -divider {Unit under test}
add wave -noupdate /port_inline_status_tb/uut/eg_reset_p
add wave -noupdate /port_inline_status_tb/uut/eg_wr_status
add wave -noupdate -radix hexadecimal /port_inline_status_tb/uut/eg_status
add wave -noupdate -radix hexadecimal /port_inline_status_tb/uut/eg_main_in
add wave -noupdate -radix hexadecimal /port_inline_status_tb/uut/eg_main_out
add wave -noupdate /port_inline_status_tb/uut/eg_err_inj
add wave -noupdate /port_inline_status_tb/uut/ig_reset_p
add wave -noupdate /port_inline_status_tb/uut/ig_wr_status
add wave -noupdate -radix hexadecimal /port_inline_status_tb/uut/ig_status
add wave -noupdate -radix hexadecimal /port_inline_status_tb/uut/ig_in_data
add wave -noupdate /port_inline_status_tb/uut/ig_in_last
add wave -noupdate /port_inline_status_tb/uut/ig_in_write
add wave -noupdate -radix hexadecimal /port_inline_status_tb/uut/ig_main_in
add wave -noupdate -radix hexadecimal /port_inline_status_tb/uut/ig_main_out
add wave -noupdate /port_inline_status_tb/uut/ig_err_fifo
add wave -noupdate /port_inline_status_tb/uut/ig_err_inj
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {192565 ns} 0}
configure wave -namecolwidth 326
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
WaveRestoreZoom {0 ns} {2625 us}
