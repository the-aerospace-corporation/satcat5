# Copyright 2019, 2022, 2023 The Aerospace Corporation
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
# This script builds the specified project, passed via command line.
# It is used as part of the Jenkins build-automation pipeline.
#

# Arguments with default values
proc setvars {projname {cfgmem_type "none"} {cfgmem_interface SPIx4} {cfgmem_size 16}} {
    upvar 1 PROJNAME PROJNAME
    upvar 1 CFGMEM_TYPE CFGMEM_TYPE
    upvar 1 CFGMEM_INTERFACE CFGMEM_INTERFACE
    upvar 1 CFGMEM_SIZE CFGMEM_SIZE
    set PROJNAME $projname
    set CFGMEM_TYPE $cfgmem_type
    set CFGMEM_INTERFACE $cfgmem_interface
    set CFGMEM_SIZE $cfgmem_size
}

# Set args
if {[llength $argv] < 1} {
    error "Must specify project! Pass with -tclargs in batch mode or set argv in GUI mode"
}
setvars $argv

# Import functions for "shared_build.tcl".
variable script_dir [file normalize [file dirname [info script]]]
source $script_dir/shared_build.tcl

# Synthesis, P&R, Bitgen
puts "Building project: $PROJNAME"
open_project ./$PROJNAME/$PROJNAME.xpr
satcat5_launch_run

# If requested, also write out the .bit or .hdf file.
# Note: OUT_NAME is set by the "create_project" or "shared_create" script.
variable prev_dir [pwd]
cd [get_property DIRECTORY [get_runs impl_1]]
if {$CFGMEM_TYPE == "zynq"} {
    satcat5_write_hdf ${OUT_NAME}.hdf
} elseif {$CFGMEM_TYPE == "cfgmem"} {
    satcat5_write_bin ${OUT_NAME}.bin $CFGMEM_INTERFACE $CFGMEM_SIZE
}
cd $prev_dir
