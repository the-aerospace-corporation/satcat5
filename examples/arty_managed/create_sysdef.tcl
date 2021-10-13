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
# Build the Vivado project (see "create_vivado.tcl") and generate the
# SYSDEF file (hardware definitions + bitfile) for import into Xilinx SDK.

puts {Running create_sysdef.tcl}

# Build bitfile (may take a while...)
# Note: Ignore "launch_runs" errors for already-finished builds.
catch {
    launch_runs impl_1 -to_step write_bitstream -jobs 4
}
puts {Waiting for completion...}
wait_on_run impl_1 -timeout 30;     # Wait for run to finish...

# Find the output we just generated.
puts {Looking for output files...}
set run_dir [get_property DIRECTORY [current_run]]
set run_bit [lindex [glob -nocomplain $run_dir/*.bit] 0]
set run_mmi [lindex [glob -nocomplain $run_dir/*.mmi] 0]

# Write out the hardware definition
puts "Writing SYSDEF:"
puts "    BIT: $run_bit"
puts "    MMI: $run_mmi"

set script_dir [file normalize [file dirname [info script]]]
write_hwdef -force -file $run_dir/arty_managed.hwdef
write_sysdef -force \
    -hwdef $run_dir/arty_managed.hwdef \
    -bitfile $run_bit \
    -meminfo $run_mmi \
    -file $script_dir/arty_managed.hdf

set sysdef_size [file size $script_dir/arty_managed.hdf]
puts "SYSDEF Ready ($sysdef_size bytes)"
