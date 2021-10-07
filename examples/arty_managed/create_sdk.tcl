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
createhw -name sdk_hw -hwspec $script_dir/arty_managed.hdf
createbsp -name sdk_bsp -hwproject sdk_hw -proc ublaze_microblaze_0 -os standalone

# Import the checked-in source folder.
# (Also includes .cproject, linker script, etc.)
importprojects sdk_src

# Build the .elf file.
puts {Starting ELF build...}
projects -build
puts {ELF ready!}
exit
