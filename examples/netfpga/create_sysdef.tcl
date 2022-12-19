# ------------------------------------------------------------------------
# Copyright 2022 The Aerospace Corporation
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
