# Copyright 2019, 2021 The Aerospace Corporation
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
add wave -noupdate -divider {Test Control}
add wave -noupdate /port_statistics_tb/test_index
add wave -noupdate /port_statistics_tb/test_start
add wave -noupdate /port_statistics_tb/test_running
add wave -noupdate /port_statistics_tb/test_frames
add wave -noupdate /port_statistics_tb/test_rx_rate
add wave -noupdate /port_statistics_tb/test_tx_rate
add wave -noupdate -divider {Statistics counters}
add wave -noupdate -radix unsigned /port_statistics_tb/tot_rx_byte
add wave -noupdate -radix unsigned /port_statistics_tb/tot_rx_frm
add wave -noupdate -radix unsigned /port_statistics_tb/tot_tx_byte
add wave -noupdate -radix unsigned /port_statistics_tb/tot_tx_frm
add wave -noupdate -radix unsigned /port_statistics_tb/ref_rx_byte
add wave -noupdate -radix unsigned /port_statistics_tb/ref_tx_byte
add wave -noupdate -divider {Unit under test}
add wave -noupdate /port_statistics_tb/stats_req_t
add wave -noupdate -radix unsigned /port_statistics_tb/uut_rx_byte
add wave -noupdate -radix unsigned /port_statistics_tb/uut_rx_frm
add wave -noupdate -radix unsigned /port_statistics_tb/uut_tx_byte
add wave -noupdate -radix unsigned /port_statistics_tb/uut_tx_frm
add wave -noupdate -divider {UUT Internals}
add wave -noupdate /port_statistics_tb/uut/u_stats/rx_isff
add wave -noupdate /port_statistics_tb/uut/u_stats/rx_eof
add wave -noupdate /port_statistics_tb/uut/u_stats/rx_last
add wave -noupdate /port_statistics_tb/uut/u_stats/p_stats_rx/frm_wcount
add wave -noupdate -radix unsigned /port_statistics_tb/uut/u_stats/p_stats_rx/frm_bytes
add wave -noupdate /port_statistics_tb/uut/u_stats/p_stats_rx/is_bcast
add wave -noupdate -radix unsigned /port_statistics_tb/uut/u_stats/rx_incr
add wave -noupdate /port_statistics_tb/uut/u_stats/tx_eof
add wave -noupdate /port_statistics_tb/uut/u_stats/tx_last
add wave -noupdate -radix unsigned /port_statistics_tb/uut/u_stats/tx_incr
add wave -noupdate -radix unsigned /port_statistics_tb/uut/u_stats/p_stats_tx/frm_bytes
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {27800064 ps} 0}
configure wave -namecolwidth 230
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
WaveRestoreZoom {0 ps} {117771182 ps}
