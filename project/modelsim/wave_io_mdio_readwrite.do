# Copyright 2020 The Aerospace Corporation
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
add wave -noupdate /io_mdio_readwrite_tb/ref_idx
add wave -noupdate /io_mdio_readwrite_tb/ref_rcount
add wave -noupdate /io_mdio_readwrite_tb/ref_wren
add wave -noupdate -radix hexadecimal /io_mdio_readwrite_tb/ref_phy
add wave -noupdate -radix hexadecimal /io_mdio_readwrite_tb/ref_reg
add wave -noupdate -radix hexadecimal /io_mdio_readwrite_tb/ref_dat
add wave -noupdate -divider {MDIO Device}
add wave -noupdate /io_mdio_readwrite_tb/mdio_clk
add wave -noupdate /io_mdio_readwrite_tb/mdio_data
add wave -noupdate -radix hexadecimal /io_mdio_readwrite_tb/rcvr_phy
add wave -noupdate -radix hexadecimal /io_mdio_readwrite_tb/rcvr_reg
add wave -noupdate -radix hexadecimal /io_mdio_readwrite_tb/rcvr_dat
add wave -noupdate /io_mdio_readwrite_tb/rcvr_rdy
add wave -noupdate -divider {Unit Under Test}
add wave -noupdate -radix hexadecimal -subitemconfig {/io_mdio_readwrite_tb/cmd_ctrl(11) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(10) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(9) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(8) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(7) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(6) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(5) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(4) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(3) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(2) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(1) {-radix hexadecimal} /io_mdio_readwrite_tb/cmd_ctrl(0) {-radix hexadecimal}} /io_mdio_readwrite_tb/cmd_ctrl
add wave -noupdate -radix hexadecimal /io_mdio_readwrite_tb/cmd_data
add wave -noupdate /io_mdio_readwrite_tb/cmd_valid
add wave -noupdate /io_mdio_readwrite_tb/cmd_ready
add wave -noupdate -radix hexadecimal -subitemconfig {/io_mdio_readwrite_tb/rd_data(15) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(14) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(13) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(12) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(11) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(10) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(9) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(8) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(7) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(6) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(5) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(4) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(3) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(2) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(1) {-radix hexadecimal} /io_mdio_readwrite_tb/rd_data(0) {-radix hexadecimal}} /io_mdio_readwrite_tb/rd_data
add wave -noupdate /io_mdio_readwrite_tb/rd_rdy
add wave -noupdate -divider {UUT Internals}
add wave -noupdate /io_mdio_readwrite_tb/uut/phy_clk_o
add wave -noupdate /io_mdio_readwrite_tb/uut/phy_data_o
add wave -noupdate /io_mdio_readwrite_tb/uut/phy_data_t
add wave -noupdate /io_mdio_readwrite_tb/uut/phy_data_i
add wave -noupdate /io_mdio_readwrite_tb/uut/phy_data_s
add wave -noupdate /io_mdio_readwrite_tb/uut/cmd_write
add wave -noupdate /io_mdio_readwrite_tb/uut/cmd_idle
add wave -noupdate /io_mdio_readwrite_tb/uut/rd_enable
add wave -noupdate /io_mdio_readwrite_tb/uut/rd_final
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {17581 ns} 0}
configure wave -namecolwidth 275
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
WaveRestoreZoom {16275 ns} {21525 ns}
