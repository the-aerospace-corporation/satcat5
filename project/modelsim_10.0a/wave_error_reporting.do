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
add wave -noupdate /error_reporting_tb/test_index
add wave -noupdate /error_reporting_tb/test_reset
add wave -noupdate /error_reporting_tb/test_ref
add wave -noupdate -divider {UART Output}
add wave -noupdate /error_reporting_tb/err_uart
add wave -noupdate /error_reporting_tb/rcvd_byte_s
add wave -noupdate -radix hexadecimal /error_reporting_tb/rcvd_data
add wave -noupdate /error_reporting_tb/msg_count
add wave -noupdate /error_reporting_tb/msg_total
add wave -noupdate -divider {UUT Internals}
add wave -noupdate /error_reporting_tb/uut/err_strobe
add wave -noupdate /error_reporting_tb/uut/err_flags
add wave -noupdate /error_reporting_tb/uut/rom_mstart
add wave -noupdate /error_reporting_tb/uut/p_read/rom_addr
add wave -noupdate -radix hexadecimal /error_reporting_tb/uut/rom_byte
add wave -noupdate /error_reporting_tb/uut/msg_start
add wave -noupdate /error_reporting_tb/uut/msg_index
add wave -noupdate /error_reporting_tb/uut/msg_busy
add wave -noupdate /error_reporting_tb/uut/uart_start
add wave -noupdate /error_reporting_tb/uut/uart_busy
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {2273608344 ps} 0}
configure wave -namecolwidth 226
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
WaveRestoreZoom {2273518094 ps} {2273774442 ps}
