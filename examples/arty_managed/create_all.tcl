# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation
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
catch {exec xsct -eval source $example_dir/create_sdk.tcl}
source $example_dir/create_bin.tcl
