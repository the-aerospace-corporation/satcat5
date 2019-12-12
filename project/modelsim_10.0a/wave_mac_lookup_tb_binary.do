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
add wave -noupdate -divider {Binary I/O}
add wave -noupdate /mac_lookup_tb/u_binary/pkt_count
add wave -noupdate /mac_lookup_tb/u_binary/pkt_mode
add wave -noupdate /mac_lookup_tb/u_binary/scrub_req
add wave -noupdate /mac_lookup_tb/u_binary/scrub_busy
add wave -noupdate /mac_lookup_tb/u_binary/scrub_count
add wave -noupdate /mac_lookup_tb/u_binary/scrub_remove
add wave -noupdate /mac_lookup_tb/u_binary/in_pdst
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_binary/in_data
add wave -noupdate /mac_lookup_tb/u_binary/in_last
add wave -noupdate /mac_lookup_tb/u_binary/in_pdst
add wave -noupdate /mac_lookup_tb/u_binary/in_psrc
add wave -noupdate /mac_lookup_tb/u_binary/in_valid
add wave -noupdate /mac_lookup_tb/u_binary/in_ready
add wave -noupdate /mac_lookup_tb/u_binary/ref_valid
add wave -noupdate /mac_lookup_tb/u_binary/ref_pdst
add wave -noupdate /mac_lookup_tb/u_binary/out_pdst
add wave -noupdate /mac_lookup_tb/u_binary/out_valid
add wave -noupdate /mac_lookup_tb/u_binary/out_ready
add wave -noupdate -divider {Binary Internals}
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/mac_psrc
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/mac_src
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/mac_dst
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/mac_ready
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/mac_valid
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/row_count
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/search_state
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/search_pdst
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/p_search/dst_idx_lo
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/p_search/dst_idx_hi
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/p_search/src_idx_lo
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/p_search/src_idx_hi
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/p_search/dst_found
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/p_search/dst_done
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/p_search/src_found
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/p_search/src_done
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/p_search/src_bcast
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/p_search/scrub_idx
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/scrub_rd_cnt
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/read_addr
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/mac_lookup_tb/u_binary/uut/gen_binary/u_mac/read_val.mac {-height 15 -radix hexadecimal} /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/read_val.mask {-height 15 -radix hexadecimal} /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/read_val.tscrub {-height 15 -radix hexadecimal}} /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/read_val
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/read_eq_dst
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/read_eq_src
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/read_lt_dst
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/read_lt_src
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/write_addr
add wave -noupdate /mac_lookup_tb/u_binary/uut/gen_binary/u_mac/write_en
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {901760870 ps} 0}
configure wave -namecolwidth 416
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
WaveRestoreZoom {901579729 ps} {901964257 ps}
