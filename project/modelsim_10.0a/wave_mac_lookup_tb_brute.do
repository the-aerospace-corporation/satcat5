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
add wave -noupdate -divider {Brute I/O}
add wave -noupdate /mac_lookup_tb/u_brute/pkt_mode
add wave -noupdate /mac_lookup_tb/u_brute/pkt_count
add wave -noupdate /mac_lookup_tb/u_brute/ignore_ovr
add wave -noupdate /mac_lookup_tb/u_brute/scrub_req
add wave -noupdate /mac_lookup_tb/u_brute/scrub_busy
add wave -noupdate /mac_lookup_tb/u_brute/scrub_count
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_brute/in_data
add wave -noupdate /mac_lookup_tb/u_brute/in_last
add wave -noupdate /mac_lookup_tb/u_brute/mac_final
add wave -noupdate /mac_lookup_tb/u_brute/in_pdst
add wave -noupdate /mac_lookup_tb/u_brute/in_psrc
add wave -noupdate /mac_lookup_tb/u_brute/in_rate
add wave -noupdate /mac_lookup_tb/u_brute/in_ready
add wave -noupdate /mac_lookup_tb/u_brute/in_valid
add wave -noupdate /mac_lookup_tb/u_brute/ref_pdst
add wave -noupdate /mac_lookup_tb/u_brute/out_pdst
add wave -noupdate /mac_lookup_tb/u_brute/out_ready
add wave -noupdate /mac_lookup_tb/u_brute/out_valid
add wave -noupdate -divider {Brute Internals}
add wave -noupdate /mac_lookup_tb/u_brute/uut/gen_brute/u_mac/table_count
add wave -noupdate /mac_lookup_tb/u_brute/uut/gen_brute/u_mac/table_wr
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_brute/uut/gen_brute/u_mac/mac_dst
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_brute/uut/gen_brute/u_mac/mac_src
add wave -noupdate /mac_lookup_tb/u_brute/uut/gen_brute/u_mac/mac_rdy
add wave -noupdate /mac_lookup_tb/u_brute/uut/gen_brute/u_mac/match_dst
add wave -noupdate /mac_lookup_tb/u_brute/uut/gen_brute/u_mac/match_src
add wave -noupdate /mac_lookup_tb/u_brute/uut/gen_brute/u_mac/match_rdy
add wave -noupdate -expand -subitemconfig {/mac_lookup_tb/u_brute/uut/gen_brute/u_mac/table_value(0).mac {-height 15 -radix hexadecimal} /mac_lookup_tb/u_brute/uut/gen_brute/u_mac/table_value(0).mask {-height 15 -radix binary}} /mac_lookup_tb/u_brute/uut/gen_brute/u_mac/table_value(0)
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {12983121 ps} 0}
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
WaveRestoreZoom {12691250 ps} {13478750 ps}
