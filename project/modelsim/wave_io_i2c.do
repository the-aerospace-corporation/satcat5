# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test control}
add wave -noupdate /io_i2c_tb/test_index
add wave -noupdate /io_i2c_tb/cmd_run
add wave -noupdate /io_i2c_tb/sclk_i
add wave -noupdate /io_i2c_tb/sdata_i
add wave -noupdate -divider UUT-Dev
add wave -noupdate -radix hexadecimal /io_i2c_tb/dev_rx_data
add wave -noupdate /io_i2c_tb/dev_rx_write
add wave -noupdate /io_i2c_tb/dev_rx_start
add wave -noupdate /io_i2c_tb/dev_rx_rdreq
add wave -noupdate /io_i2c_tb/dev_rx_stop
add wave -noupdate -radix hexadecimal /io_i2c_tb/dev_tx_data
add wave -noupdate /io_i2c_tb/dev_tx_valid
add wave -noupdate /io_i2c_tb/dev_tx_ready
add wave -noupdate /io_i2c_tb/uut_dev/sclk_o
add wave -noupdate /io_i2c_tb/uut_dev/sclk_i
add wave -noupdate /io_i2c_tb/uut_dev/sdata_o
add wave -noupdate /io_i2c_tb/uut_dev/sdata_i
add wave -noupdate /io_i2c_tb/uut_dev/i2c_state
add wave -noupdate /io_i2c_tb/uut_dev/i2c_bcount
add wave -noupdate -radix hexadecimal /io_i2c_tb/uut_dev/i2c_rxbuff
add wave -noupdate -divider UUT-Ctrl
add wave -noupdate -radix hexadecimal /io_i2c_tb/tx_opcode
add wave -noupdate -radix hexadecimal /io_i2c_tb/tx_data
add wave -noupdate /io_i2c_tb/tx_valid
add wave -noupdate /io_i2c_tb/tx_ready
add wave -noupdate -radix hexadecimal /io_i2c_tb/rx_data
add wave -noupdate /io_i2c_tb/rx_write
add wave -noupdate /io_i2c_tb/bus_stop
add wave -noupdate /io_i2c_tb/bus_noack
add wave -noupdate /io_i2c_tb/uut_ctrl/sclk_o
add wave -noupdate /io_i2c_tb/uut_ctrl/sclk_i
add wave -noupdate /io_i2c_tb/uut_ctrl/sdata_o
add wave -noupdate /io_i2c_tb/uut_ctrl/sdata_i
add wave -noupdate /io_i2c_tb/uut_ctrl/clk_rnext
add wave -noupdate /io_i2c_tb/uut_ctrl/clk_wnext
add wave -noupdate /io_i2c_tb/uut_ctrl/byte_read
add wave -noupdate /io_i2c_tb/uut_ctrl/byte_final
add wave -noupdate /io_i2c_tb/uut_ctrl/cmd_bcount
add wave -noupdate /io_i2c_tb/uut_ctrl/cmd_noack
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {144500 ns} 0}
configure wave -namecolwidth 219
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
WaveRestoreZoom {138850 ns} {151978 ns}
