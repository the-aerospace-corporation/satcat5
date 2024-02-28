# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Xilinx AC701 dev board,
# with a single SGMII port using four of the SMA connectors (2 Tx, 2 Rx).
# The design does not contain a switch, only a loopback test designed to
# generate traffic and measure error-rate statistics.
#
# To re-create the project, source this file in the Vivado Tcl Shell.
#

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_proj "loopback_ac701"
set target_part "xc7a200tfbg676-2"
set target_top "loopback_ac701_top"
set constr_synth "loopback_ac701_synth.xdc"
set constr_impl "loopback_ac701_impl.xdc"

# List HDL source files, grouped by type.
set files_main [list \
 "[file normalize "../../src/vhdl/common/*.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/clkgen_sgmii.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_*.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/port_sgmii_gpio.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_data_slip.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_data_sync.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_input_fifo.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_rx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_tx.vhd"]"\
 "[file normalize "./loopback_ac701_top.vhd"]"\
]

# Run the main script.
source ../../project/vivado/shared_create.tcl
