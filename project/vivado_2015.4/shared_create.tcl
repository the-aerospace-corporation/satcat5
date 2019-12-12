# ------------------------------------------------------------------------
# Copyright 2019 The Aerospace Corporation
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
# This script is a target-agnostic helper that is used by the various
# "create_xx" project creation scripts, to increase code reuse.  It is
# not typically run directly.
#

# Create project and set properties.
set obj [create_project $target_proj ./$target_proj -force]
set_property "default_lib" "xil_defaultlib" $obj
set_property "part" $target_part $obj
set_property "sim.ip.auto_export_scripts" "1" $obj
set_property "simulator_language" "Mixed" $obj
set_property "target_language" "VHDL" $obj
set proj_dir [get_property directory [current_project]]

# Make a copy of the dummy "debug" constraints file.
file copy -force "./shared_debug.xdc" "./$target_proj/constr_debug.xdc"

# Add each file and set properties.
set src_files [get_filesets sources_1]

foreach fi $files_main {
    set file_obj [add_files -norecurse -fileset $src_files $fi]
    set_property "file_type" "VHDL" $file_obj
    set_property "library" "xil_defaultlib" $file_obj
}

set_property "top" $target_top $src_files

# Create the Soft Error Mitigation (SEM) core.
source generate_sem.tcl
generate_sem sem_0

# Add/Import each constraints file and set properties.
#create_fileset -constrset constrs_1
set constr_files [get_filesets constrs_1]

set file "[file normalize ./$constr_synth]"
set file_added [add_files -norecurse -fileset $constr_files $file]
set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
set_property "file_type" "XDC" $file_obj

set file "[file normalize ./$constr_impl]"
set file_added [add_files -norecurse -fileset $constr_files $file]
set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
set_property "file_type" "XDC" $file_obj
set_property "used_in" "implementation" $file_obj
set_property "used_in_synthesis" "0" $file_obj

set file "[file normalize ./$target_proj/constr_debug.xdc]"
set file_added [add_files -norecurse -fileset $constr_files $file]
set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
set_property "file_type" "XDC" $file_obj

# Set 'sim_1' fileset object
#create_fileset -simset sim_1
set obj [get_filesets sim_1]
set_property "top" $target_top $obj
set_property "xelab.nosort" "1" $obj
set_property "xelab.unifast" "" $obj

# Create 'synth_1' run (if not found)
if {[string equal [get_runs -quiet synth_1] ""]} {
  create_run -name synth_1 -part $target_part -flow {Vivado Synthesis 2015} -strategy "Vivado Synthesis Defaults" -constrset constrs_1
} else {
  set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
  set_property flow "Vivado Synthesis 2015" [get_runs synth_1]
}
set obj [get_runs synth_1]
set_property "needs_refresh" "1" $obj
set_property "part" $target_part $obj
set_property "steps.synth_design.tcl.pre" "$proj_dir/../shared_presynth.tcl" $obj
set_property "steps.synth_design.args.more options" -value "-generic BUILD_DATE=\$TCL_BUILD_DATE" -object $obj
current_run -synthesis [get_runs synth_1]

# Create 'impl_1' run (if not found)
if {[string equal [get_runs -quiet impl_1] ""]} {
  create_run -name impl_1 -part $target_part -flow {Vivado Implementation 2015} -strategy "Vivado Implementation Defaults" -constrset constrs_1 -parent_run synth_1
} else {
  set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]
  set_property flow "Vivado Implementation 2015" [get_runs impl_1]
}
set obj [get_runs impl_1]
set_property "needs_refresh" "1" $obj
set_property "part" $target_part $obj
set_property "steps.write_bitstream.args.readback_file" "0" $obj
set_property "steps.write_bitstream.args.verbose" "0" $obj
set_property "STEPS.WRITE_BITSTREAM.TCL.POST" "$proj_dir/../shared_postbit.tcl" $obj
current_run -implementation [get_runs impl_1]

# Done!
puts "INFO: Project created!"
