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
