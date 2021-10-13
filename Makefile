# Copyright 2020, 2021 The Aerospace Corporation
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
VIVADO_VERSION ?= 2016.3

# Also export version so that it's in the env for any scripts
# that get called from this Makefile (e.g. xsim_run.sh)
export VIVADO_VERSION := ${VIVADO_VERSION}

# Shortcuts for running Vivado in batch mode.
# Special case for fake-GUI mode using XVFB (required for SDK)
VIVADO_SETUP := source /opt/Xilinx/Vivado/${VIVADO_VERSION}/settings64.sh
VIVADO_BATCH := vivado -mode batch -nojournal -nolog -notrace -source
VIVADO_RUN := ${VIVADO_SETUP} && ${VIVADO_BATCH}
VIVADO_GUI := ${VIVADO_SETUP} && xvfb-run -a ${VIVADO_BATCH}
VIVADO_BUILD := ${VIVADO_RUN} ../../project/vivado/build_project.tcl -tclargs

# Set working folders
SIMS_DIR := ./sim/vhdl/
SW_TEST_DIR := ./sim/cpp

# Simulations
.PHONY: sims
sims:
	@cd ${SIMS_DIR} && source xsim_run.sh
	@cd ${SIMS_DIR} && python xsim_parse.py

# Various configurations of the 1st-gen prototype using AC701
.PHONY: proto_v1_base
proto_v1_base:
	@cd examples/ac701_proto_v1 && ${VIVADO_RUN} create_project_proto_v1_base.tcl
	@cd examples/ac701_proto_v1 && ${VIVADO_BUILD} switch_proto_v1_base

.PHONY: proto_v1_rgmii
proto_v1_rgmii:
	@cd examples/ac701_proto_v1 && ${VIVADO_RUN} create_project_proto_v1_rgmii.tcl
	@cd examples/ac701_proto_v1 && ${VIVADO_BUILD} switch_proto_v1_rgmii

.PHONY: proto_v1_sgmii
proto_v1_sgmii:
	@cd examples/ac701_proto_v1 && ${VIVADO_RUN} create_project_proto_v1_sgmii.tcl
	@cd examples/ac701_proto_v1 && ${VIVADO_BUILD} switch_proto_v1_sgmii

# 2nd-gen prototype using integrated custom PCB
.PHONY: proto_v2
proto_v2:
	@cd examples/proto_v2 && ${VIVADO_RUN} create_project_proto_v2.tcl
	@cd examples/proto_v2 && ${VIVADO_BUILD} switch_proto_v2

# Arty-A7 example design (Artix7-35T or Artix7-100T)
.PHONY: arty_35t
arty_35t:
	@cd examples/arty_a7 && ${VIVADO_RUN} create_project_arty_a7.tcl -tclargs 35T
	@cd examples/arty_a7 && ${VIVADO_BUILD} switch_arty_a7_35t

.PHONY: arty_100t
arty_100t:
	@cd examples/arty_a7 && ${VIVADO_RUN} create_project_arty_a7.tcl -tclargs 100T
	@cd examples/arty_a7 && ${VIVADO_BUILD} switch_arty_a7_100t

.PHONY: arty_managed_35t
arty_managed_35t:
	@cd examples/arty_managed && ${VIVADO_GUI} create_all.tcl -tclargs 35T

.PHONY: arty_managed_100t
arty_managed_100t:
	@cd examples/arty_managed && ${VIVADO_GUI} create_all.tcl -tclargs 100T

# Example router design using AC701.
.PHONY: ac701_router
ac701_router:
	@cd examples/ac701_router && ${VIVADO_RUN} create_project_router_ac701.tcl
	@cd examples/ac701_router && ${VIVADO_BUILD} router_ac701

# Example design for ZedBoard.
.PHONY: zed_converter
zed_converter:
	@cd examples/zed_converter && ${VIVADO_RUN} create_project_converter_zed.tcl
	@cd examples/zed_converter && ${VIVADO_BUILD} converter_zed

# Example design for MPF splash kit
.PHONY: mpf_splash
mpf_splash:
	@cd examples/mpf_splash && ./make_project.sh

# Example design for iCE40 HX8K board
.PHONY: ice40_rmii_serial
ice40_rmii_serial:
	@cd examples/ice40_hx8k && ./yosys_ice40_hx8k.sh switch_top_rmii_serial_adapter

# Build and run software tests
.PHONY: sw_test
sw_test:
	@cd ${SW_TEST_DIR} && make test

# Run software tests and then generate coverage reports
.PHONY: sw_coverage
sw_coverage:
	@cd ${SW_TEST_DIR} && make coverage

# Run software tests and pass/fail based on code coverage
.PHONY: sw_covertest
sw_covertest:
	@cd ${SW_TEST_DIR} && make coverage_test
