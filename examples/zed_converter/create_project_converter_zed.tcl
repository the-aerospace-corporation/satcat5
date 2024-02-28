# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Avnet Zedboard,
# demonstrating a SatCat5 translation for the PS ethernet peripheral.
# To re-create the project, source this file in the Vivado Tcl Shell.
#

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_proj "converter_zed"
set target_part "XC7Z020CLG484-1"
set target_board "em.avnet.com:zed:part0:1.3"

set target_top "converter_zed_top"
set constr_synth "converter_zed_synth.xdc"
set constr_impl "converter_zed_impl.xdc"

# List HDL source files, grouped by type.
set files_main [list \
 "[file normalize "../../src/vhdl/common/common_functions.vhd"]"\
 "[file normalize "../../src/vhdl/common/common_primitives.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_adjust.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_check.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_frame_common.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_preamble_rx.vhd"]"\
 "[file normalize "../../src/vhdl/common/eth_preamble_tx.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_packet.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_priority.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_smol_async.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_smol_resize.vhd"]"\
 "[file normalize "../../src/vhdl/common/fifo_smol_sync.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_error_reporting.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_leds.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_spi_controller.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_spi_peripheral.vhd"]"\
 "[file normalize "../../src/vhdl/common/io_uart.vhd"]"\
 "[file normalize "../../src/vhdl/common/packet_delay.vhd"]"\
 "[file normalize "../../src/vhdl/common/packet_inject.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_adapter.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_passthrough.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_serial_auto.vhd"]"\
 "[file normalize "../../src/vhdl/common/slip_decoder.vhd"]"\
 "[file normalize "../../src/vhdl/common/slip_encoder.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_types.vhd"]"\
 "[file normalize "../../src/vhdl/common/port_gmii_internal.vhd"]"\
 "[file normalize "../../src/vhdl/common/switch_dual.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_io.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_mem.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_sync.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/scrub_xilinx.vhd"]"\
 "[file normalize "./converter_zed_top.vhd"]"\
]

# Run the main script.
source ../../project/vivado/shared_create.tcl

# Create block design
create_bd_design "ps"

# Configure ps
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
set ps7_obj [get_bd_cells processing_system7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {apply_board_preset "1" Master "Disable" Slave "Disable" }  $ps7_obj
set_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ  {125} $ps7_obj
set_property CONFIG.PCW_ENET1_PERIPHERAL_ENABLE   {1} $ps7_obj
set_property CONFIG.PCW_TTC0_PERIPHERAL_ENABLE    {0} $ps7_obj
set_property CONFIG.PCW_USE_M_AXI_GP0             {0} $ps7_obj

# Export necessary signals
# backwards-compatible alternative to
# make_bd_intf_pins_external -name ps_gmii [get_bd_intf_pins processing_system7_0/GMII_ETHERNET_1]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gmii_rtl:1.0 ps_gmii
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/GMII_ETHERNET_1] [get_bd_intf_ports ps_gmii]
# backwards-compatible alternative to
# make_bd_pins_external      -name clk_125 [get_bd_pins processing_system7_0/FCLK_CLK0]
# make_bd_pins_external      -name ps_reset_n [get_bd_pins processing_system7_0/FCLK_RESET0_N]
create_bd_port -dir O -type clk clk_125
connect_bd_net [get_bd_pins /processing_system7_0/FCLK_CLK0] [get_bd_ports clk_125]
create_bd_port -dir O -type rst ps_reset_n
connect_bd_net [get_bd_pins /processing_system7_0/FCLK_RESET0_N] [get_bd_ports ps_reset_n]

# Save block design
save_bd_design
make_wrapper -import -top -files [get_files ps.bd]
close_bd_design [get_bd_designs ps]

# unset to avoid interference with future runs
unset target_board

# Execute the build and write out the .bin file.
source ../../project/vivado/shared_build.tcl
satcat5_launch_run
satcat5_write_hdf $target_top.hdf
