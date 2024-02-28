# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Prototype V2 target
# in the standard configuration (i.e., 5 GigE ports + 8 SPI/UART ports).
# To re-create the project, source this file in the Vivado Tcl Shell.
#

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties.
set target_proj "switch_proto_v2"
set target_part "xc7a50tftg256-2"
set target_top "switch_top_proto_v2"
set constr_synth "switch_proto_v2_synth.xdc"
set constr_impl "switch_proto_v2_impl.xdc"

# List HDL source files, grouped by type.
set files_main [list \
 "[file normalize "../../src/vhdl/common/common_functions.vhd"]"\
 "[file normalize "../../src/vhdl/common/common_primitives.vhd"]"\
 "[file normalize "../../src/vhdl/common/cfgbus_common.vhd"]"\
 "[file normalize "../../src/vhdl/common/cfgbus_host_eth.vhd"]"\
 "[file normalize "../../src/vhdl/common/cfgbus_mdio.vhd"]"\
 "[file normalize "../../src/vhdl/common/config_peripherals.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_dec8b10b.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_enc8b10b.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_enc8b10b_table.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_adjust.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_check.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_common.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_vstrip.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_vtag.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_pause_ctrl.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_preamble_rx.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_preamble_tx.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_packet.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_priority.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_repack.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_smol_async.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_smol_resize.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_smol_sync.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_error_reporting.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_leds.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_mdio_readwrite.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_spi_controller.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_spi_peripheral.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_uart.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_core.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_counter.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_igmp_simple.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_lookup.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_priority.vhd"]"\
 "[file normalize "../../src/vhdl/common/mac_vlan_mask.vhd"]"\
 "[file normalize "../../src/vhdl/common/packet_delay.vhd"]"\
 "[file normalize "../../src/vhdl/common/packet_inject.vhd"]"\
 "[file normalize "../../src/vhdl/common/packet_round_robin.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_cfgbus.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_crosslink.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_sgmii_common.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_serial_auto.vhd"]"\
 "[file normalize "../../src/vhdl/common/slip_decoder.vhd"]"\
 "[file normalize "../../src/vhdl/common/slip_encoder.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_aux.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_core.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_types.vhd"]"\
 "[file normalize "../../src/vhdl/common/tcam_cache_nru2.vhd"]"\
 "[file normalize "../../src/vhdl/common/tcam_cache_plru.vhd"]"\
 "[file normalize "../../src/vhdl/common/tcam_core.vhd"]"\
 "[file normalize "../../src/vhdl/common/tcam_maxlen.vhd"]"\
 "[file normalize "../../src/vhdl/common/tcam_table.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/clkgen_sgmii.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_io.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_mem.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_sync.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/port_sgmii_gpio.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/scrub_xilinx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_data_slip.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_data_sync.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_input_fifo.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_rx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_tx.vhd"]"\
 "[file normalize "./switch_top_proto_v2.vhd"]"\
]

# Run the main script.
source ../../project/vivado/shared_create.tcl

# Execute the build and write out the .bin file.
source ../../project/vivado/shared_build.tcl
satcat5_launch_run
satcat5_write_bin $target_top.bin
