# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Digilent Arty A7
# target, in either the "Artix7-35T" or "Artix7-100T" configurations.
# To re-create the project, source this file in the Vivado Tcl Shell.
#

# USER picks one of the Arty board options (35t or 100t), or default to 35t.
# (Pass with -tclargs in batch mode or "set argv" in GUI mode.)
if {[llength $argv] == 1} {
    set BOARD_OPTION [string tolower [lindex $argv 0]]
} else {
    set BOARD_OPTION "35t"
}

set VALID_BOARDS [list "35t" "100t"]
if {($BOARD_OPTION in $VALID_BOARDS)} {
    puts "Targeting Arty Artix7-$BOARD_OPTION"
} else {
    error "Must choose BOARD_OPTION from [list $VALID_BOARDS]"
}

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_proj "switch_arty_a7_$BOARD_OPTION"
if {[string equal $BOARD_OPTION "100t"]} {
    set target_part "XC7A100TCSG324-1"
} else {
    set target_part "XC7A35TICSG324-1L"
}
set target_top "switch_top_arty_a7_rmii"
set constr_synth "switch_arty_a7_synth.xdc"
set constr_impl "switch_arty_a7_impl.xdc"
set bin_config [list SPIx4, 16]

# List HDL source files, grouped by type.
set files_main [list \
 "[file normalize "../../src/vhdl/common/*.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/clkgen_rmii.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/7series_*.vhd"]"\
 "[file normalize "../../src/vhdl/xilinx/scrub_xilinx.vhd"]"\
 "[file normalize "./switch_top_arty_a7_rmii.vhd"]"\
]

# Run the main script.
source ../../project/vivado/shared_create.tcl

# Execute the build and write out the .bin file.
source ../../project/vivado/shared_build.tcl
satcat5_launch_run
satcat5_write_bin $target_top.bin
