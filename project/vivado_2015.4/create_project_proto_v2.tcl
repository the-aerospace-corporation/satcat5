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
# This script creates a new Vivado project for the Prototype V2 target
# in the standard configuration (i.e., 5 GigE ports + 8 SPI/UART ports).
# To re-create the project, source this file in the Vivado Tcl Shell.
#

# Set project-level properties.
set target_proj "switch_proto_v2"
set target_part "xc7a50tftg256-2"
set target_top "switch_top_proto_v2"
set constr_synth "./switch_proto_v2_synth.xdc"
set constr_impl "./switch_proto_v2_impl.xdc"

# List HDL source files, grouped by type.
set files_main [list \
 "[file normalize "../../src/vhdl/common/common_types.vhd"]"\
 "[file normalize "../../src/vhdl/common/config_port_eth.vhd"]"\
 "[file normalize "../../src/vhdl/common/config_read_command.vhd"]"\
 "[file normalize "../../src/vhdl/common/config_send_status.vhd"]"\
 "[file normalize "../../src/vhdl/common/error_reporting.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_dec8b10b.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_enc8b10b.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_enc8b10b_table.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_adjust.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_check.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_common.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_preambles.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_mdio_master.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_spi_master.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_spi_slave.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_uart.vhd"]"\
 "[file normalize "../../src/vhdl/common/led_types.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_binary.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_brute.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_generic.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_parshift.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_simple.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup_stream.vhd"]"\
 "[file normalize "../../src/vhdl/common/packet_delay.vhd"]"\
 "[file normalize "../../src/vhdl/common/packet_fifo.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_crosslink.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_sgmii_common.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_serial_auto.vhd"]"\
 "[file normalize "../../src/vhdl/common/round_robin.vhd"]"\
 "[file normalize "../../src/vhdl/common/slip_decoder.vhd"]"\
 "[file normalize "../../src/vhdl/common/slip_encoder.vhd"]"\
 "[file normalize "../../src/vhdl/common/smol_fifo.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_aux.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_core.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_types.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/clkgen_sgmii.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/io_7series.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/port_sgmii_xilinx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/scrub_xilinx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_data_slip.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_data_sync.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_input_fifo.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_rx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_tx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/synchronization.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/switch_top_proto_v2.vhd"]"\
]

# Run the main script.
source shared_create.tcl
