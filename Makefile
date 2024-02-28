# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.


# Use BASH shell for the "source" command.
SHELL := /bin/bash

# If tool version isn't specified, use the default.
VIVADO_VERSION ?= 2016.3

# Also export version so that it's in the env for any scripts
# that get called from this Makefile (e.g. xsim_run.sh)
export VIVADO_VERSION := ${VIVADO_VERSION}

# Shortcuts for running Vivado in batch mode.
# Always set a fake GUI environment with XVFB, for SDK and block-diagram export.
VIVADO_SETUP := source /opt/Xilinx/Vivado/${VIVADO_VERSION}/settings64.sh
VIVADO_BATCH := vivado -mode batch -nojournal -nolog -notrace -source
VIVADO_RUN := ${VIVADO_SETUP} && xvfb-run -a ${VIVADO_BATCH}

# Software analysis parameters
CPPCHECK_RUN := cppcheck \
    --std=c++11 --enable=all --xml --xml-version=2 \
    -DSATCAT5_IRQ_STATS=1 \
    -DSATCAT5_VLAN_ENABLE=1 \
    -i src/cpp/hal_ublaze/overrides.cc \
    -i src/cpp/qcbor \
    --suppress=knownConditionTrueFalse \
    --suppress=missingInclude \
    --suppress=unusedFunction
CPPLINT_FILTERS := \
    -build/include_order, -build/include_what_you_use, -build/include_subdir, \
    -readability/casting, -readability/namespace, -readability/todo, \
    -runtime/indentation_namespace, -runtime/references, \
    -whitespace, +whitespace/end_of_line, +whitespace/tab
CPPLINT_RUN := cpplint \
    --filter=$(subst $() ,,$(CPPLINT_FILTERS)) \
    --exclude=src/cpp/hal_test/catch.hpp \
    --exclude=src/cpp/qcbor/* \
    --verbose=1 --recursive

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

.PHONY: proto_v1_rgmii
proto_v1_rgmii:
	@cd examples/ac701_proto_v1 && ${VIVADO_RUN} create_project_proto_v1_rgmii.tcl

.PHONY: proto_v1_sgmii
proto_v1_sgmii:
	@cd examples/ac701_proto_v1 && ${VIVADO_RUN} create_project_proto_v1_sgmii.tcl

# 2nd-gen prototype using integrated custom PCB
.PHONY: proto_v2
proto_v2:
	@cd examples/proto_v2 && ${VIVADO_RUN} create_project_proto_v2.tcl

# Arty-A7 example design (Artix7-35T or Artix7-100T)
.PHONY: arty_35t
arty_35t:
	@cd examples/arty_a7 && ${VIVADO_RUN} create_project_arty_a7.tcl -tclargs 35T

.PHONY: arty_100t
arty_100t:
	@cd examples/arty_a7 && ${VIVADO_RUN} create_project_arty_a7.tcl -tclargs 100T

.PHONY: arty_managed_35t
arty_managed_35t:
	@cd examples/arty_managed && ${VIVADO_RUN} create_all.tcl -tclargs 35T

.PHONY: arty_managed_100t
arty_managed_100t:
	@cd examples/arty_managed && ${VIVADO_RUN} create_all.tcl -tclargs 100T

# Example router design using AC701.
.PHONY: ac701_router
ac701_router:
	@cd examples/ac701_router && ${VIVADO_RUN} create_project_router_ac701.tcl

# NetFPGA example design
.PHONY: netfpga
netfpga:
	@cd examples/netfpga && ${VIVADO_RUN} create_all.tcl

# VC707 example designs
.PHONY: vc707_clksynth
vc707_clksynth:
	@cd examples/vc707_clksynth && ${VIVADO_RUN} create_vivado.tcl

.PHONY: vc707_managed
vc707_managed:
	@cd examples/vc707_managed && ${VIVADO_RUN} create_all.tcl

.PHONY: vc707_ptp_client
vc707_ptp_client:
	@cd examples/vc707_ptp_client && ${VIVADO_RUN} create_all.tcl

# ZCU208 example design
.PHONY: zcu208_clksynth
zcu208_clksynth:
	@cd examples/zcu208_clksynth && ${VIVADO_RUN} create_vivado.tcl

# Example design for ZedBoard.
.PHONY: zed_converter
zed_converter:
	@cd examples/zed_converter && ${VIVADO_RUN} create_project_converter_zed.tcl

# Example design for MPF splash kit
.PHONY: mpf_splash
mpf_splash:
	@cd examples/mpf_splash && ./make_project.sh

# Example design for iCE40 HX8K board
.PHONY: ice40_rmii_serial
ice40_rmii_serial:
	@cd examples/ice40_hx8k && ./yosys_ice40_hx8k.sh switch_top_rmii_serial_adapter

# Build and run the Log-Viewer tool
.PHONY: log_viewer
log_viewer:
	@cd test/log_viewer && make run

# Build each of the C++ example tools.
.PHONY: sw_tools
sw_tools:
	@cd examples/arty_managed/oled_demo && make all
	@cd examples/zcu208_clksynth/config_tool && make all
	@cd test/log_viewer && make all

# Build and run software tests
.PHONY: sw_test
sw_test:
	@cd ${SW_TEST_DIR} && make test

# Run software tests and then generate coverage reports
.PHONY: sw_coverage
sw_coverage:
	@cd ${SW_TEST_DIR} && make clean
	@cd ${SW_TEST_DIR} && make coverage

# Run software tests and pass/fail based on code coverage
.PHONY: sw_covertest
sw_covertest:
	@cd ${SW_TEST_DIR} && make coverage_test

# Run "cppcheck" static analyzer on C++ software
.PHONY: sw_cppcheck
sw_cppcheck:
	@${CPPCHECK_RUN} src/cpp 2> cppcheck.xml

# Run "cpplint" linter on C++ software
.PHONY: sw_cpplint
sw_cpplint:
	@${CPPLINT_RUN} src/cpp 2> cpplint.log

# Build and run python software tests
# Note: Run with "sudo" or grant CAP_NET_RAW to the Python executable.
#   e.g., "sudo setcap cap_net_raw+eip /usr/bin/python3.6".
.PHONY: sw_python
sw_python:
	@cd sim/python && python3 cfgbus_test.py
