# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Prototype V1 target
# (AC701 + custom I/O board) in the "SGMII" configuration.
# To re-create the project, source this file in the Vivado Tcl Shell.
#

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties.
set target_proj "switch_proto_v1_sgmii"
set target_part "xc7a200tfbg676-2"
set target_top "switch_top_ac701_sgmii"
set constr_synth "switch_proto_v1_sgmii_synth.xdc"
set constr_impl "switch_proto_v1_sgmii_impl.xdc"

# List HDL source files, grouped by type.
set files_main [list \
 "[file normalize "../../src/vhdl/common/*.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/clkgen_sgmii.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_*.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/port_sgmii_gpio.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/scrub_xilinx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_data_slip.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_data_sync.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_input_fifo.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_rx.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_tx.vhd"]"\
 "[file normalize "./switch_top_ac701_sgmii.vhd"]"\
]

# Run the main script.
source ../../project/vivado/shared_create.tcl

# Execute the build and write out the .bin file.
source ../../project/vivado/shared_build.tcl
satcat5_launch_run
satcat5_write_bin $target_top.bin
