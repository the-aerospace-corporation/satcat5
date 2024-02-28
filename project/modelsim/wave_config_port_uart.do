# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Test control}
add wave -noupdate /config_port_uart_tb/cmd_index
add wave -noupdate -radix hexadecimal /config_port_uart_tb/cmd_opcode
add wave -noupdate /config_port_uart_tb/uart_host
add wave -noupdate -divider {Test outputs}
add wave -noupdate -radix hexadecimal /config_port_uart_tb/ctrl_out
add wave -noupdate /config_port_uart_tb/spi_csb
add wave -noupdate /config_port_uart_tb/spi_sck
add wave -noupdate /config_port_uart_tb/spi_sdo
add wave -noupdate /config_port_uart_tb/mdio_clk
add wave -noupdate /config_port_uart_tb/mdio_data
add wave -noupdate -divider {Unit Under Test}
add wave -noupdate -radix hexadecimal /config_port_uart_tb/uut/uart_data
add wave -noupdate /config_port_uart_tb/uut/uart_write
add wave -noupdate -radix hexadecimal /config_port_uart_tb/uut/slip_data
add wave -noupdate /config_port_uart_tb/uut/slip_write
add wave -noupdate /config_port_uart_tb/uut/slip_last
add wave -noupdate /config_port_uart_tb/uut/u_cmd/opcode_spi
add wave -noupdate /config_port_uart_tb/uut/u_cmd/opcode_gpo
add wave -noupdate /config_port_uart_tb/uut/u_cmd/opcode_mdany
add wave -noupdate /config_port_uart_tb/uut/u_cmd/opcode_mdio
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {758349867 ps} 0}
configure wave -namecolwidth 208
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
WaveRestoreZoom {748614290 ps} {781426790 ps}
