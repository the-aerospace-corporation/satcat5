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
add wave -noupdate -divider {Simple I/O}
add wave -noupdate /mac_lookup_tb/u_simple/pkt_mode
add wave -noupdate /mac_lookup_tb/u_simple/pkt_count
add wave -noupdate /mac_lookup_tb/u_simple/scrub_count
add wave -noupdate /mac_lookup_tb/u_simple/scrub_req
add wave -noupdate /mac_lookup_tb/u_simple/scrub_busy
add wave -noupdate /mac_lookup_tb/u_simple/scrub_remove
add wave -noupdate /mac_lookup_tb/u_simple/in_pdst
add wave -noupdate /mac_lookup_tb/u_simple/in_psrc
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_simple/in_data
add wave -noupdate /mac_lookup_tb/u_simple/in_last
add wave -noupdate /mac_lookup_tb/u_simple/in_valid
add wave -noupdate /mac_lookup_tb/u_simple/in_ready
add wave -noupdate /mac_lookup_tb/u_simple/ref_pdst
add wave -noupdate /mac_lookup_tb/u_simple/out_pdst
add wave -noupdate /mac_lookup_tb/u_simple/out_ready
add wave -noupdate /mac_lookup_tb/u_simple/out_valid
add wave -noupdate -divider {Simple Internals}
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/mac_dst
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/mac_src
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/mac_rdy
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/row_count
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/row_delete
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/row_insert
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/search_state
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/search_addr
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/mac_lookup_tb/u_simple/uut/gen_simple/u_mac/search_rdval.mac {-height 15 -radix hexadecimal} /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/search_rdval.mask {-height 15 -radix hexadecimal} /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/search_rdval.tscrub {-height 15 -radix hexadecimal}} /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/search_rdval
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/search_dst
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/search_done
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/search_wren
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/scrub_state
add wave -noupdate /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/scrub_addr
add wave -noupdate -radix hexadecimal -expand -subitemconfig {/mac_lookup_tb/u_simple/uut/gen_simple/u_mac/scrub_rdval.mac {-height 15 -radix hexadecimal} /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/scrub_rdval.mask {-height 15 -radix hexadecimal} /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/scrub_rdval.tscrub {-height 15 -radix hexadecimal}} /mac_lookup_tb/u_simple/uut/gen_simple/u_mac/scrub_rdval
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {734265000 ps} 0}
configure wave -namecolwidth 328
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
WaveRestoreZoom {0 ps} {2100 us}
