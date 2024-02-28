# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Prototype V1 target
# (AC701 + custom I/O board) in the "RGMII" configuration.
# To re-create the project, source this file in the Vivado Tcl Shell.
#

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties.
set target_part "xc7a200tfbg676-2"
set target_proj "switch_proto_v1_rgmii"
set target_top "switch_top_ac701_rgmii"
set constr_synth "switch_proto_v1_rgmii_synth.xdc"
set constr_impl "switch_proto_v1_rgmii_impl.xdc"

# List HDL source files, grouped by type.
set files_main [list \
 "[file normalize "../../src/vhdl/common/*.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/clkgen_rgmii.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_*.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/scrub_xilinx.vhd"]"\
 "[file normalize "./switch_top_ac701_rgmii.vhd"]"\
]

# Run the main script.
source ../../project/vivado/shared_create.tcl

# Execute the build and write out the .bin file.
source ../../project/vivado/shared_build.tcl
satcat5_launch_run
satcat5_write_bin $target_top.bin
