# ------------------------------------------------------------------------
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
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Prototype V1 target
# (AC701 + custom I/O board) in the "RGMII" configuration.
# To re-create the project, source this file in the Vivado Tcl Shell.
#

# Set project-level properties.
set target_part "xc7a200tfbg676-2"
set target_proj "switch_proto_v1_rgmii"
set target_top "switch_top_ac701_rgmii"
set constr_synth "constraints/switch_proto_v1_rgmii_synth.xdc"
set constr_impl "constraints/switch_proto_v1_rgmii_impl.xdc"

# List HDL source files, grouped by type.
set files_main [list \
 "[file normalize "../../src/vhdl/common/common_functions.vhd"]"\
 "[file normalize "../../src/vhdl/common/config_port_eth.vhd"]"\
 "[file normalize "../../src/vhdl/common/config_port_uart.vhd"]"\
 "[file normalize "../../src/vhdl/common/config_read_command.vhd"]"\
 "[file normalize "../../src/vhdl/common/config_send_status.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_adjust.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_check.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_common.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_preambles.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_packet.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_smol.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_error_reporting.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_leds.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_mdio_writer.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_spi_clkin.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_spi_clkout.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_uart.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_binary.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_brute.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_generic.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_lutram.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_parshift.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_simple.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_stream.vhd"]"\
 "[file normalize "../../src/vhdl/common/packet_delay.vhd"]"\
 "[file normalize "../../src/vhdl/common/packet_round_robin.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_crosslink.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_rgmii.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_serial_auto.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_serial_spi_clkin.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_serial_uart_2wire.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_serial_uart_4wire.vhd"]"\
 "[file normalize "../../src/vhdl/common/slip_decoder.vhd"]"\
 "[file normalize "../../src/vhdl/common/slip_encoder.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_aux.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_core.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_types.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/clkgen_rgmii.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/io_7series.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/lcd_control.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/lutram_7series.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/scrub_xilinx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/synchronization.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/switch_top_ac701_rgmii.vhd"]"\
]

# Run the main script.
source shared_create.tcl
