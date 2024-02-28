# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------

puts {Running shared_postbit.tcl}

# NOTE: Automatic path lookup is COMPLICATED in the TCL-hook context.
# The latter has various complicated context-shenanigans, more info here:
# https://forums.xilinx.com/t5/Vivado-TCL-Community/using-tcl-hook-scripts/td-p/398221
# Upside is that "current_project" and "current_run" work fine when run from
# the TCL console, but have no defined meaning when run as pre/post hooks.
if [info exists current_run] {
    # If running from console, use "current_run" command:
    set SRC_DIR [get_property DIRECTORY [current_run]]
    set TARGET_DEVICE [get_property part [current_project]]
} else {
    # If running as a hook, use "pwd" to point to the active run.
    set SRC_DIR [pwd]
    set TARGET_DEVICE [get_property part [get_projects]]
}

# Set destination folder by relative path.
set DST_DIR $SRC_DIR/../../../backups
file mkdir $DST_DIR

# Create timestamp string.
set TIME_NOW [clock seconds]
set TIME_STR [clock format $TIME_NOW -format %Y%m%d_%H%M]

# For each file in that folder we want to archive...
cd $SRC_DIR
foreach BITFILE [glob -nocomplain *.bit *.mmi] {
    # Remove the ".bit" suffix (last four characters).
    set FILE_STRLEN [string length $BITFILE]
    set FILE_EXT [string range $BITFILE $FILE_STRLEN-3 $FILE_STRLEN]
    set DESIGN_NAME [string range $BITFILE 0 $FILE_STRLEN-5]
    # Append timestamp to the design name.
    set OUT_NAME ${DST_DIR}/${DESIGN_NAME}_${TIME_STR}
    # Copy the file and derived outputs to the destination folder.
    file copy -force $BITFILE ${OUT_NAME}.$FILE_EXT
}
