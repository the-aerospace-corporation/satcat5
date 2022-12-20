# Copyright 2022 The Aerospace Corporation
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
add wave -noupdate /ptp_realtime_tb/in_last
add wave -noupdate /ptp_realtime_tb/in_write
add wave -noupdate -radix unsigned /ptp_realtime_tb/time_now
add wave -noupdate -radix unsigned /ptp_realtime_tb/time_rdref
add wave -noupdate -radix unsigned /ptp_realtime_tb/time_rdval
add wave -noupdate -radix unsigned /ptp_realtime_tb/time_sof
add wave -noupdate -radix unsigned /ptp_realtime_tb/cfg_opcode
add wave -noupdate -radix unsigned -expand -subitemconfig {/ptp_realtime_tb/cfg_cmd.clk {-height 15 -radix unsigned} /ptp_realtime_tb/cfg_cmd.sysaddr {-height 15 -radix unsigned} /ptp_realtime_tb/cfg_cmd.devaddr {-height 15 -radix unsigned} /ptp_realtime_tb/cfg_cmd.regaddr {-height 15 -radix unsigned} /ptp_realtime_tb/cfg_cmd.wdata {-height 15 -radix unsigned} /ptp_realtime_tb/cfg_cmd.wstrb {-height 15 -radix unsigned} /ptp_realtime_tb/cfg_cmd.wrcmd {-height 15 -radix unsigned} /ptp_realtime_tb/cfg_cmd.rdcmd {-height 15 -radix unsigned} /ptp_realtime_tb/cfg_cmd.reset_p {-height 15 -radix unsigned}} /ptp_realtime_tb/cfg_cmd
add wave -noupdate -radix unsigned /ptp_realtime_tb/cfg_ack
add wave -noupdate -radix unsigned /ptp_realtime_tb/cfg_rdval
add wave -noupdate /ptp_realtime_tb/test_index
add wave -noupdate /ptp_realtime_tb/pkt_start
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {3225 ns} 0}
configure wave -namecolwidth 243
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
WaveRestoreZoom {3113 ns} {3337 ns}
