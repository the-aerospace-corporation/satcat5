# ------------------------------------------------------------------------
# Copyright 2021-2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# Run each step to produce a finished "Arty-Managed" bitfile:
#   * Create Vivado project.
#   * Build Vivado project into SYSDEF.
#   * Create and build SDK projects.
#   * Produce final .bit and .bin artifacts.
#
# Note: Requires top-level argument for board type ("35t" or "100t")

puts {Creating Arty-Managed example design...}

variable example_dir [file normalize [file dirname [info script]]]
source $example_dir/create_vivado.tcl
source $example_dir/create_sysdef.tcl
# XSCT returns error even if successful -> Ignore it.
catch { exec xsct -eval source $example_dir/create_sdk.tcl >@stdout }
source $example_dir/create_bin.tcl
