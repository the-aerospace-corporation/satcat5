# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
