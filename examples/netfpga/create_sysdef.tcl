# ------------------------------------------------------------------------
# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# Build the Vivado project (see "create_vivado.tcl") and generate the
# SYSDEF file (hardware definitions + bitfile) for import into Xilinx SDK.

puts {Running create_sysdef.tcl}

# Import functions for "shared_build.tcl".
variable script_dir [file normalize [file dirname [info script]]]
source $script_dir/../../project/vivado/shared_build.tcl

# Build bitfile (may take a while...)
satcat5_launch_run

# Write out the hardware definition
satcat5_write_hdf $script_dir/netfpga.hdf
