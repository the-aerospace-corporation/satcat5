# ------------------------------------------------------------------------
# Copyright 2019, 2020, 2021 The Aerospace Corporation
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
