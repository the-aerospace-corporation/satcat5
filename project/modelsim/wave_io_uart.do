# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix unsigned /io_uart_tb/rate_div
add wave -noupdate -radix hexadecimal /io_uart_tb/tx_data
add wave -noupdate /io_uart_tb/tx_valid
add wave -noupdate /io_uart_tb/tx_ready
add wave -noupdate /io_uart_tb/tx_break
add wave -noupdate -radix hexadecimal /io_uart_tb/rx_data
add wave -noupdate /io_uart_tb/rx_write
add wave -noupdate /io_uart_tb/rx_break
add wave -noupdate -radix hexadecimal /io_uart_tb/ref_data
add wave -noupdate /io_uart_tb/ref_wren
add wave -noupdate /io_uart_tb/ref_valid
add wave -noupdate -divider {UART signal}
add wave -noupdate -color Red /io_uart_tb/uart
add wave -noupdate -divider {Tx Internals}
add wave -noupdate /io_uart_tb/uut_tx/t_ready
add wave -noupdate /io_uart_tb/uut_tx/t_bit_count
add wave -noupdate -radix unsigned /io_uart_tb/uut_tx/t_clk_count
add wave -noupdate /io_uart_tb/uut_tx/t_brk_hold
add wave -noupdate -radix hexadecimal /io_uart_tb/uut_tx/t_sreg
add wave -noupdate -divider {Rx Internals}
add wave -noupdate -radix hexadecimal /io_uart_tb/uut_rx/r_data
add wave -noupdate /io_uart_tb/uut_rx/r_write
add wave -noupdate /io_uart_tb/uut_rx/r_break
add wave -noupdate /io_uart_tb/uut_rx/r_bit_count
add wave -noupdate -radix unsigned /io_uart_tb/uut_rx/r_clk_count
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {56824095 ps} 0}
configure wave -namecolwidth 202
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
WaveRestoreZoom {56457539 ps} {58098171 ps}
