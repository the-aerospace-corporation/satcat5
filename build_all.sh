#!/bin/bash
# Copyright 2019 The Aerospace Corporation
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

# Abort immediately on any non-zero return code.
set -e

# Configure environment
export RUN_VIVADO="vivado -mode batch -nojournal -nolog -notrace -source"
source /opt/Xilinx/Vivado/2015.4/settings64.sh
cd ./project/vivado_2015.4

# Create each Vivado project
$RUN_VIVADO create_project_proto_v1_base.tcl
$RUN_VIVADO create_project_proto_v1_rgmii.tcl
$RUN_VIVADO create_project_proto_v1_sgmii.tcl
$RUN_VIVADO create_project_proto_v2.tcl
$RUN_VIVADO create_project_arty_a7.tcl -tclargs 35T
$RUN_VIVADO create_project_arty_a7.tcl -tclargs 100T

# Build each Vivado project
# (Note that project names are case-sensitive!)
$RUN_VIVADO build_project.tcl -tclargs switch_proto_v1_base
$RUN_VIVADO build_project.tcl -tclargs switch_proto_v1_rgmii
$RUN_VIVADO build_project.tcl -tclargs switch_proto_v1_sgmii
$RUN_VIVADO build_project.tcl -tclargs switch_proto_v2
$RUN_VIVADO build_project.tcl -tclargs switch_arty_a7_35t
$RUN_VIVADO build_project.tcl -tclargs switch_arty_a7_100t
