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
add wave -noupdate -divider {Test Status}
add wave -noupdate /eth_all8b10b_tb/test_idx
add wave -noupdate /eth_all8b10b_tb/test_shift
add wave -noupdate /eth_all8b10b_tb/test_rate
add wave -noupdate /eth_all8b10b_tb/test_txen
add wave -noupdate -divider {Input stream}
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/in_data
add wave -noupdate /eth_all8b10b_tb/in_dv
add wave -noupdate /eth_all8b10b_tb/in_cken
add wave -noupdate -divider {Output and reference}
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/out_port
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/ref_data
add wave -noupdate /eth_all8b10b_tb/ref_last
add wave -noupdate -divider {Configuration word}
add wave -noupdate /eth_all8b10b_tb/cfg_txen
add wave -noupdate /eth_all8b10b_tb/cfg_rcvd
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/cfg_txdata
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/cfg_rxdata
add wave -noupdate -divider {Encoder internals}
add wave -noupdate /eth_all8b10b_tb/uut_enc/strm_state
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/uut_enc/strm_data
add wave -noupdate /eth_all8b10b_tb/uut_enc/strm_ctrl
add wave -noupdate /eth_all8b10b_tb/uut_enc/strm_even
add wave -noupdate /eth_all8b10b_tb/uut_enc/strm_cfgct
add wave -noupdate /eth_all8b10b_tb/uut_enc/strm_cken
add wave -noupdate -divider {Decoder internals}
add wave -noupdate -radix hexadecimal /eth_all8b10b_tb/uut_dec/align_data
add wave -noupdate /eth_all8b10b_tb/uut_dec/align_cken
add wave -noupdate /eth_all8b10b_tb/uut_dec/align_lock
add wave -noupdate /eth_all8b10b_tb/uut_dec/p_align/align_bit
add wave -noupdate /eth_all8b10b_tb/uut_dec/p_align/count_comma
add wave -noupdate /eth_all8b10b_tb/uut_dec/p_align/count_other
add wave -noupdate /eth_all8b10b_tb/uut_dec/p_meta/cfg_tok
add wave -noupdate /eth_all8b10b_tb/uut_dec/p_meta/cfg_ctr
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {99389426 ps} 0}
configure wave -namecolwidth 360
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
WaveRestoreZoom {98521344 ps} {100077824 ps}
