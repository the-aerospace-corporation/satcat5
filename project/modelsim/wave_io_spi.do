# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

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
