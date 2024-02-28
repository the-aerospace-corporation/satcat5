# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
