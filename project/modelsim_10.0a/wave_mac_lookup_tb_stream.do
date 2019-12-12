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
add wave -noupdate -divider {Stream I/O}
add wave -noupdate /mac_lookup_tb/u_stream/pkt_count
add wave -noupdate /mac_lookup_tb/u_stream/pkt_mode
add wave -noupdate /mac_lookup_tb/u_stream/in_pdst
add wave -noupdate /mac_lookup_tb/u_stream/in_psrc
add wave -noupdate -radix hexadecimal /mac_lookup_tb/u_stream/in_data
add wave -noupdate /mac_lookup_tb/u_stream/in_last
add wave -noupdate /mac_lookup_tb/u_stream/in_valid
add wave -noupdate /mac_lookup_tb/u_stream/in_ready
add wave -noupdate /mac_lookup_tb/u_stream/ref_pdst
add wave -noupdate /mac_lookup_tb/u_stream/ref_valid
add wave -noupdate /mac_lookup_tb/u_stream/out_pdst
add wave -noupdate /mac_lookup_tb/u_stream/out_valid
add wave -noupdate /mac_lookup_tb/u_stream/out_ready
add wave -noupdate -divider {Stream Internals}
add wave -noupdate /mac_lookup_tb/u_stream/uut/gen_stream/u_mac/in_wr_src
add wave -noupdate /mac_lookup_tb/u_stream/uut/gen_stream/u_mac/in_wr_dst
add wave -noupdate /mac_lookup_tb/u_stream/uut/gen_stream/u_mac/match_bcast
add wave -noupdate /mac_lookup_tb/u_stream/uut/gen_stream/u_mac/match_flag
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {4999588565 ps} 0}
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
WaveRestoreZoom {4999220696 ps} {5000041016 ps}
