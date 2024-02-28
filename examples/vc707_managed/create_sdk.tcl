# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# Import the SYSDEF file ("create_sysdef.tcl") from Vivado and set up the
# three required SDK projects: Hardware, Board Support Package, Software.

puts {Running create_sdk.tcl}

# Set Eclipse workspace to the script folder.
set script_dir [file normalize [file dirname [info script]]]
setws $script_dir

# Clean up working folders
puts {Clearing old SDK folders...}
file delete -force $script_dir/.metadata
file delete -force $script_dir/sdk_hw
file delete -force $script_dir/sdk_bsp

# Create a new board support package.
puts {Creating new SDK projects...}
createhw -name sdk_hw -hwspec $script_dir/vc707_managed.hdf
createbsp -name sdk_bsp -hwproject sdk_hw -proc ublaze0_microblaze_0 -os standalone

# Import the checked-in source folder.
# (Also includes .cproject, linker script, etc.)
importprojects sdk_src

# Build the .elf file.
puts {Starting ELF build...}
projects -build
puts {ELF ready!}
exit
