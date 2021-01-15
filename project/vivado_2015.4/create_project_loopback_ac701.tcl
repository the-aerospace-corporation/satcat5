# ------------------------------------------------------------------------
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
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Xilinx AC701 dev board,
# with a single SGMII port using four of the SMA connectors (2 Tx, 2 Rx).
# The design does not contain a switch, only a loopback test designed to
# generate traffic and measure error-rate statistics.
#
# To re-create the project, source this file in the Vivado Tcl Shell.
#

# Set project-level properties depending on the selected board.
set target_proj "loopback_ac701"
set target_part "xc7a200tfbg676-2"
set target_top "loopback_ac701_top"
set constr_synth "constraints/loopback_ac701_synth.xdc"
set constr_impl "constraints/loopback_ac701_impl.xdc"

# List HDL source files, grouped by type.
set files_main [list \
 "[file normalize "../../src/vhdl/common/common_functions.vhd"]"\
 "[file normalize "../../src/vhdl/common/config_port_test.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_dec8b10b.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_enc8b10b.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_enc8b10b_table.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_adjust.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_check.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_common.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_preambles.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_traffic_src.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_smol.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_leds.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_uart.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_sgmii_common.vhd"]"\
 "[file normalize "../../src/vhdl/common/slip_encoder.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_types.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/clkgen_sgmii.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/io_7series.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/lcd_control.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/port_sgmii_gpio.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_data_slip.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_data_sync.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_input_fifo.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_rx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_tx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/synchronization.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/loopback_ac701_top.vhd"]"\
]

# Run the main script.
source shared_create.tcl
