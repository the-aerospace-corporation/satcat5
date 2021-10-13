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
# Given a completed SDK build, create the final .bit and .bin files.
#

puts {Running create_bin.tcl}

# Create timestamp string.
set time_now [clock seconds]
set time_str [clock format $time_now -format %Y%m%d_%H%M]

# Pull input files from the SDK workspace.
set script_dir [file normalize [file dirname [info script]]]
set file_ref $script_dir/sdk_hw/arty_managed_wrapper
set file_elf $script_dir/sdk_src/Debug/sdk_src.elf
set file_out $script_dir/arty_managed_$time_str

# Confirm expected files are present:
proc does_file_exist {filename} {
    if {[file exist $filename]} {
        puts "Checking $filename -> OK"
    } else {
        puts "Checking $filename -> Not found"
    }
}

does_file_exist $file_elf
does_file_exist $file_ref.bit
does_file_exist $file_ref.mmi

# Fold .elf file into provided .bit file.
# (The original .bit and .mmi files are embedded in the .sysdef.)
exec updatemem -force \
    -proc arty_managed_i/ublaze/microblaze_0 \
    -data $file_elf \
    -meminfo $file_ref.mmi \
    -bit $file_ref.bit \
    -out $file_out.bit

does_file_exist $file_out.bit

# Convert .bit file into .bin for flashing boot-PROM.
write_cfgmem -force -format BIN -interface SPIx4 -size 16 \
    -loadbit "up 0x0 $file_out.bit" $file_out.bin
