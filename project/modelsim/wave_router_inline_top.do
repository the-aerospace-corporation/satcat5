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
add wave -noupdate -divider {Test control}
add wave -noupdate /router_inline_top_tb/test_idx_hi
add wave -noupdate /router_inline_top_tb/test_idx_lo
add wave -noupdate -divider {Ingress stream}
add wave -noupdate -radix hexadecimal /router_inline_top_tb/ref_ig_data
add wave -noupdate /router_inline_top_tb/ref_ig_last
add wave -noupdate /router_inline_top_tb/ref_ig_valid
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut_ig_data
add wave -noupdate /router_inline_top_tb/uut_ig_last
add wave -noupdate /router_inline_top_tb/uut_ig_write
add wave -noupdate -divider {Egress stream}
add wave -noupdate -radix hexadecimal /router_inline_top_tb/ref_eg_data
add wave -noupdate /router_inline_top_tb/ref_eg_last
add wave -noupdate /router_inline_top_tb/ref_eg_valid
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut_eg_data
add wave -noupdate /router_inline_top_tb/uut_eg_last
add wave -noupdate /router_inline_top_tb/uut_eg_write
add wave -noupdate -divider {ARP Queries}
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/query_first
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/query_addr
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/query_valid
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/query_ready
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/reply_first
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/reply_match
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/reply_addr
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/reply_write
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/request_first
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/request_addr
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/request_write
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/update_first
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/update_addr
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/update_valid
add wave -noupdate /router_inline_top_tb/uut/ig_prox_en/u_ig_proxy/update_ready
add wave -noupdate -divider {Internal streams}
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/inbuf_data
add wave -noupdate /router_inline_top_tb/uut/inbuf_write
add wave -noupdate /router_inline_top_tb/uut/inbuf_commit
add wave -noupdate /router_inline_top_tb/uut/inbuf_revert
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/ig_inbuf
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/ig_gate
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/ig_proxy
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/ig_out
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/eg_inraw
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/router_inline_top_tb/uut/eg_nocrc.data {-height 15 -radix hexadecimal} /router_inline_top_tb/uut/eg_nocrc.last {-height 15 -radix hexadecimal} /router_inline_top_tb/uut/eg_nocrc.valid {-height 15 -radix hexadecimal} /router_inline_top_tb/uut/eg_nocrc.ready {-height 15 -radix hexadecimal}} /router_inline_top_tb/uut/eg_nocrc
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/eg_nocrc_write
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/eg_gate
add wave -noupdate -radix hexadecimal /router_inline_top_tb/uut/eg_out
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {47849 ns} 0}
configure wave -namecolwidth 325
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
WaveRestoreZoom {47555 ns} {47887 ns}
