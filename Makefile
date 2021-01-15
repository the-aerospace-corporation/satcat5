# Copyright 2020 The Aerospace Corporation
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

# Use BASH shell for the "source" command.
SHELL := /bin/bash

# If tool version isn't specified, use the default.
VIVADO_VERSION ?= 2015.4
VIVADO_SETUP := source /opt/Xilinx/Vivado/${VIVADO_VERSION}/settings64.sh
VIVADO_BUILD := vivado -mode batch -nojournal -nolog -notrace -source
RUN_VIVADO := ${VIVADO_SETUP} && ${VIVADO_BUILD}

# Also export it so that it's in the env for any scripts
# that get called from this Makefile (e.g. xsim_run.sh)
export VIVADO_VERSION := ${VIVADO_VERSION}

# Set working folders
SIMS_DIR := ./sim/vhdl/
PROJ_DIR := ./project/vivado_2015.4

# Simulations
.PHONY: sims
sims:
	@cd ${SIMS_DIR} && source xsim_run.sh
	@cd ${SIMS_DIR} && python xsim_parse.py

# Various configurations of the 1st-gen prototype using AC701
.PHONY: proto_v1_base
proto_v1_base:
	@cd ${PROJ_DIR} && ${RUN_VIVADO} create_project_proto_v1_base.tcl
	@cd ${PROJ_DIR} && ${RUN_VIVADO} build_project.tcl -tclargs switch_proto_v1_base

.PHONY: proto_v1_rgmii
proto_v1_rgmii:
	@cd ${PROJ_DIR} && ${RUN_VIVADO} create_project_proto_v1_rgmii.tcl
	@cd ${PROJ_DIR} && ${RUN_VIVADO} build_project.tcl -tclargs switch_proto_v1_rgmii

.PHONY: proto_v1_sgmii
proto_v1_sgmii:
	@cd ${PROJ_DIR} && ${RUN_VIVADO} create_project_proto_v1_sgmii.tcl
	@cd ${PROJ_DIR} && ${RUN_VIVADO} build_project.tcl -tclargs switch_proto_v1_sgmii

# 2nd-gen prototype using integrated custom PCB
.PHONY: proto_v2
proto_v2:
	@cd ${PROJ_DIR} && ${RUN_VIVADO} create_project_proto_v2.tcl
	@cd ${PROJ_DIR} && ${RUN_VIVADO} build_project.tcl -tclargs switch_proto_v2

# Arty-A7 example design (Artix7-35T or Artix7-100T)
.PHONY: arty_35t
arty_35t:
	@cd ${PROJ_DIR} && ${RUN_VIVADO} create_project_arty_a7.tcl -tclargs 35T
	@cd ${PROJ_DIR} && ${RUN_VIVADO} build_project.tcl -tclargs switch_arty_a7_35t

.PHONY: arty_100t
arty_100t:
	@cd ${PROJ_DIR} && ${RUN_VIVADO} create_project_arty_a7.tcl -tclargs 100T
	@cd ${PROJ_DIR} && ${RUN_VIVADO} build_project.tcl -tclargs switch_arty_a7_100t

# Example router design using AC701.
.PHONY: router_ac701
router_ac701:
	@cd ${PROJ_DIR} && ${RUN_VIVADO} create_project_router_ac701.tcl
	@cd ${PROJ_DIR} && ${RUN_VIVADO} build_project.tcl -tclargs router_ac701

# Example design for ZedBoard.
.PHONY: converter_zed
converter_zed:
	@cd ${PROJ_DIR} && ${RUN_VIVADO} create_project_converter_zed.tcl
	@cd ${PROJ_DIR} && ${RUN_VIVADO} build_project.tcl -tclargs converter_zed
