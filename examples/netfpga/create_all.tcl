# ------------------------------------------------------------------------
# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# Run each step to produce a finished "NetFPGA-Managed" bitfile:
#   * Create Vivado project.
#   * Build Vivado project into SYSDEF.
#   * Create and build SDK projects.
#   * Produce final .bit and .bin artifacts.
#

puts {Creating NetFPGA-Managed example design...}

variable example_dir [file normalize [file dirname [info script]]]
source $example_dir/create_vivado.tcl
source $example_dir/create_sysdef.tcl
# XSCT returns error even if successful -> Ignore it.
catch { exec xsct -eval source $example_dir/create_sdk.tcl >@stdout }
source $example_dir/create_bin.tcl
