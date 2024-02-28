# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
# Source this script in the Vivado TCL shell to create a new project
# for running unit-test simulations, located at "./vivado_sims".
#

# Change to the folder containing this script.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_proj "vivado_sims"
set target_part "xc7a200tfbg676-2"
set target_top "switch_core"

# List HDL source files, grouped by type.
set files_main [list \
 "[file normalize "../../src/vhdl/common/*.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_*.vhd"]"\
]

set files_sim [list \
 "[file normalize "../../sim/vhdl/*.vhd"]"\
]

# Run the main script.
source ../../project/vivado/shared_create.tcl

# Set default top-level for simulation.
set_property top switch_core_tb [get_filesets sim_1]
