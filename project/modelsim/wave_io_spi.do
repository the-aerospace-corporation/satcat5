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
add wave -noupdate -divider UUT0
add wave -noupdate /io_spi_tb/uut0/spi_csb
add wave -noupdate /io_spi_tb/uut0/spi_sck
add wave -noupdate /io_spi_tb/uut0/spi_copi
add wave -noupdate /io_spi_tb/uut0/spi_cipo
add wave -noupdate -radix hexadecimal /io_spi_tb/uut0/rxa_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut0/rxa_data
add wave -noupdate /io_spi_tb/uut0/rxa_write
add wave -noupdate -radix hexadecimal /io_spi_tb/uut0/rxb_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut0/rxb_data
add wave -noupdate /io_spi_tb/uut0/rxb_write
add wave -noupdate -divider UUT1
add wave -noupdate /io_spi_tb/uut1/spi_csb
add wave -noupdate /io_spi_tb/uut1/spi_sck
add wave -noupdate /io_spi_tb/uut1/spi_copi
add wave -noupdate /io_spi_tb/uut1/spi_cipo
add wave -noupdate -radix hexadecimal /io_spi_tb/uut1/rxa_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut1/rxa_data
add wave -noupdate /io_spi_tb/uut1/rxa_write
add wave -noupdate -radix hexadecimal /io_spi_tb/uut1/rxb_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut1/rxb_data
add wave -noupdate /io_spi_tb/uut1/rxb_write
add wave -noupdate -divider UUT2
add wave -noupdate /io_spi_tb/uut2/spi_csb
add wave -noupdate /io_spi_tb/uut2/spi_sck
add wave -noupdate /io_spi_tb/uut2/spi_copi
add wave -noupdate /io_spi_tb/uut2/spi_cipo
add wave -noupdate -radix hexadecimal /io_spi_tb/uut2/rxa_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut2/rxa_data
add wave -noupdate /io_spi_tb/uut2/rxa_write
add wave -noupdate -radix hexadecimal /io_spi_tb/uut2/rxb_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut2/rxb_data
add wave -noupdate /io_spi_tb/uut2/rxb_write
add wave -noupdate -divider UUT3
add wave -noupdate /io_spi_tb/uut3/spi_csb
add wave -noupdate /io_spi_tb/uut3/spi_sck
add wave -noupdate /io_spi_tb/uut3/spi_copi
add wave -noupdate /io_spi_tb/uut3/spi_cipo
add wave -noupdate -radix hexadecimal /io_spi_tb/uut3/rxa_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut3/rxa_data
add wave -noupdate /io_spi_tb/uut3/rxa_write
add wave -noupdate -radix hexadecimal /io_spi_tb/uut3/rxb_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut3/rxb_data
add wave -noupdate /io_spi_tb/uut3/rxb_write
add wave -noupdate -divider UUT4
add wave -noupdate /io_spi_tb/uut4/spi_csb
add wave -noupdate /io_spi_tb/uut4/spi_sck
add wave -noupdate /io_spi_tb/uut4/spi_copi
add wave -noupdate /io_spi_tb/uut4/spi_cipo
add wave -noupdate -radix hexadecimal /io_spi_tb/uut4/rxa_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut4/rxa_data
add wave -noupdate /io_spi_tb/uut4/rxa_write
add wave -noupdate -radix hexadecimal /io_spi_tb/uut4/rxb_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut4/rxb_data
add wave -noupdate /io_spi_tb/uut4/rxb_write
add wave -noupdate -divider UUT5
add wave -noupdate /io_spi_tb/uut5/spi_csb
add wave -noupdate /io_spi_tb/uut5/spi_sck
add wave -noupdate /io_spi_tb/uut5/spi_copi
add wave -noupdate /io_spi_tb/uut5/spi_cipo
add wave -noupdate -radix hexadecimal /io_spi_tb/uut5/rxa_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut5/rxa_data
add wave -noupdate /io_spi_tb/uut5/rxa_write
add wave -noupdate -radix hexadecimal /io_spi_tb/uut5/rxb_ref
add wave -noupdate -radix hexadecimal /io_spi_tb/uut5/rxb_data
add wave -noupdate /io_spi_tb/uut5/rxb_write
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {236 ns} 0}
configure wave -namecolwidth 238
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
WaveRestoreZoom {1387 ns} {1623 ns}
