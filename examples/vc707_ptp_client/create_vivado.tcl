# ------------------------------------------------------------------------
# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Xilinx VC707 dev board,
# with a block diagram as the top level (i.e., using packaged IP-cores).
# To re-create the project, source this file in the Vivado Tcl Shell.

puts {Running create_vivado.tcl}

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_part "XC7VX485TFFG1761-2"
set target_proj "vc707_ptp"
set constr_synth "vc707_synth.xdc"
set constr_impl "vc707_impl.xdc"
set override_postbit ""

# There's no source in this project except the IP-cores!
set files_main ""

# Run the main project-creation script and install IP-cores.
source ../../project/vivado/shared_create.tcl
source ../../project/vivado/shared_ipcores.tcl
set proj_dir [get_property directory [current_project]]

# Create the specialized synthesizer IP-core for this example.
source ./synth_mgt_from_rtc.tcl

# Link to the VC707 board for predefined named interfaces (e.g., DDR3, SGMII)
set_property board_part xilinx.com:vc707:part0:1.4 [current_project]

# Suppress specific warnings in the Vivado GUI:
set_msg_config -suppress -id {[Common 17-55]};          # Timing constraints "set_property" is empty
set_msg_config -suppress -id {[Designutils 20-1280]};   # False-alarm "Cound not find module..."
set_msg_config -suppress -id {[Place 30-574]};          # Clock on a non-clock IO pad (CLOCK_DEDICATED_ROUTE)
set_msg_config -suppress -id {[Project 1-486]};         # Block diagram black-box (false alarm)
set_msg_config -suppress -id {[Timing 38-316]};         # Block diagram clock mismatch

# Demote critical warning for clock constraint overrides, which are used
# in "vc707_impl.xdc" as a workaround for a bug in the Transceiver Wizard.
set_msg_config -new_severity WARNING -id {[Constraints 18-1056]}

# Create the block diagram.
# (Keeping this separate makes it easier to update and re-export.)
source ./create_ublaze.tcl

# Cleanup
regenerate_bd_layout
save_bd_design
validate_bd_design

# Export block design in PDF and SVG form.
source ../../project/vivado/export_bd_image.tcl

# Create block-diagram wrapper and set as top level.
set wrapper [make_wrapper -files [get_files vc707_ptp.bd] -top]
add_files -norecurse $wrapper
set_property "top" vc707_ptp_wrapper [get_filesets sources_1]
