# ------------------------------------------------------------------------
# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script is a target-agnostic helper that is used by the various
# "create_xx" project creation scripts, to increase code reuse.  It is
# not typically run directly, but as the final step in a separate project
# creation script. Refer to Xilinx example designs under "../../examples".
#
# Define the following variables before sourcing this script:
# * files_main (required)
#   A list of VHDL files to be used for synthesis. Wildcards are allowed.
#   Example:
#     set files_main [list \
#      "[file normalize "../../src/vhdl/common/*.vhd"]"\
#      "[file normalize "../../src/vhdl/xilinx/clkgen_rmii.vhd"]"\
#      "[file normalize "../../src/vhdl/xilinx/7series_*.vhd"]"\
#      "[file normalize "../../src/vhdl/xilinx/scrub_xilinx.vhd"]"\
#      "[file normalize "./switch_top_arty_a7_rmii.vhd"]"\
#     ]
# * target_part (required)
#   Full FPGA part number, including package information.
#   Example: set target_part "XC7VX485TFFG1761-2"
# * target_proj (required)
#   Name for the new Vivado project that will be created.
#   The location will be relative to the current working directory (pwd):
#     ./$target_proj/$target_proj.xpr
#   Example: set target_proj "vc707_ptp"
#
# Additional parameter variables are optional:
# * files_sim (optional)
#   Additional files for simulation only. Same format as "files_main".
# * override_script_dir (optional)
#   By default, various event hooks run additional scripts from the folder
#   containing this file. To run different scripts, specify an alternate path.
# * override_postbit (optional)
#   By default, the "post-bitfile" event hook runs "./shared_postbit.tcl".
#   To override this, set override_postbit to the empty string (skip) or
#   to the full path of the desired TCL script.
# * target_board (optional)
#   For projects on pre-installed development boards, optionally pull
#   constraints and other parameters from the named board support package.
# * target_lib (optional)
#   Override the target VHDL library. Default is "xil_defaultlib".
# * target_top (recommended)
#   Set the top-level entity. (Note: Use entity name, not filename.)
#   Example: set target_top "switch_top_arty_a7_rmii"
# * constr_synth (recommended)
#   Set constraints to be used during synthesis and all later build steps.
#   Example: set constr_synth "vc707_synth.xdc"
# * constr_impl (recommended)
#   Set constraints to be used during implementation / place-and-route.
#   Example: set constr_impl "vc707_impl.xdc"
#

puts {Running shared_create.tcl}

# Create project and set properties.
variable obj [create_project $target_proj ./$target_proj -force]
set_property "default_lib" "xil_defaultlib" $obj
set_property "part" $target_part $obj
set_property "sim.ip.auto_export_scripts" "1" $obj
set_property "simulator_language" "Mixed" $obj
set_property "target_language" "VHDL" $obj
variable proj_dir [get_property directory [current_project]]

# Set board if defined
if {[info exists target_board]} {
    set_property "board_part" $target_board $obj
}

# Helper scripts are usually in the current working folder,
# but certain configurations need to override this setting.
if {[info exists override_script_dir]} {
    set script_dir $override_script_dir
} else {
    set script_dir [file normalize [file dirname [info script]]]
}

# Enable or disable the post-bit helper script.
if {[info exists override_postbit]} {
    set postbit_script "$override_postbit"
} else {
    set postbit_script "$script_dir/shared_postbit.tcl"
}

# Default puts all files from $files_main into "xil_defaultlib",
# but user can override target library as needed.
if {![info exists target_lib]} {
    set target_lib "xil_defaultlib"
}

# Make a copy of the dummy "debug" constraints file.
file copy -force "$script_dir/debug_placeholder.xdc" "./$target_proj/constr_debug.xdc"

# Demote certain warnings that are known to be benign.
set_msg_config -new_severity INFO -id {[BD 41-1771]};           # Board vs. port name mismatch
set_msg_config -new_severity INFO -id {[Common 18-540]};        # Ignore empty set_max_delay
set_msg_config -new_severity INFO -id {[Constraints 18-540]};   # Ignore empty set_max_delay
set_msg_config -new_severity INFO -id {[Constraints 18-550]};   # Impl constraints during synth
set_msg_config -new_severity INFO -id {[Opt 31-35]};            # Removing redundant IBUF
set_msg_config -new_severity INFO -id {[Power 33-332]};         # Inaccurate power estimate
set_msg_config -new_severity INFO -id {[Synth 8-506]};          # Removed null port
set_msg_config -new_severity INFO -id {[Synth 8-3301]};         # Unused generic parameter
set_msg_config -new_severity INFO -id {[Synth 8-3331]};         # Unconnected null port
set_msg_config -new_severity INFO -id {[Synth 8-3332]};         # Unused sequential element
set_msg_config -new_severity INFO -id {[Synth 8-3819]};         # Unspecified generic parameter
set_msg_config -new_severity INFO -id {[Synth 8-3919]};         # Null assignment (width = 0)
set_msg_config -new_severity INFO -id {[Synth 8-3936]};         # Trim excess bits from register
set_msg_config -new_severity INFO -id {[Synth 8-6014]};         # Trim unused sequential element
set_msg_config -suppress          -id {[Vivado 12-3645]};       # Adding one file at a time

# Add each file and set properties.
variable src_files [get_filesets sources_1]

foreach fi $files_main {
    variable file_obj [add_files -norecurse -fileset $src_files [glob $fi]]
    set_property "file_type" "VHDL" $file_obj
    set_property "library" $target_lib $file_obj
}

# Create the Soft Error Mitigation (SEM) core.
source "$script_dir/generate_sem.tcl"
generate_sem sem_0

# Add/Import each constraints file and set properties.
variable constr_files [get_filesets constrs_1]

if {[info exists constr_synth]} {
    variable file "[file normalize ./$constr_synth]"
    variable file_added [add_files -norecurse -fileset $constr_files $file]
    variable file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
    set_property "file_type" "XDC" $file_obj
}

if {[info exists constr_impl]} {
    variable file "[file normalize ./$constr_impl]"
    variable file_added [add_files -norecurse -fileset $constr_files $file]
    variable file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
    set_property "file_type" "XDC" $file_obj
    set_property "used_in" "implementation" $file_obj
    set_property "used_in_synthesis" "0" $file_obj
}

variable file "[file normalize ./$target_proj/constr_debug.xdc]"
variable file_added [add_files -norecurse -fileset $constr_files $file]
variable file_obj [get_files -of_objects [get_filesets constrs_1] [list "*$file"]]
set_property "file_type" "XDC" $file_obj

# Set 'sim_1' fileset object
variable sim_files [get_filesets sim_1]
set_property "xelab.nosort" "1" $sim_files
set_property "xelab.unifast" "" $sim_files

if {[info exists files_sim]} {
    foreach fi $files_sim {
        variable file_obj [add_files -norecurse -fileset $sim_files [glob $fi]]
        set_property "file_type" "VHDL" $file_obj
        set_property "library" $target_lib $file_obj
    }
}

# Set the top-level file, if specified.
if {[info exists target_top]} {
    set_property "top" $target_top $src_files
    set_property "top" $target_top $sim_files
}

# Create 'synth_1' run (if not found)
if {[string equal [get_runs -quiet synth_1] ""]} {
  create_run -name synth_1 -part $target_part -flow {Vivado Synthesis 2015} -strategy "Vivado Synthesis Defaults" -constrset constrs_1
} else {
  set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
  set_property flow "Vivado Synthesis 2015" [get_runs synth_1]
}
variable obj [get_runs synth_1]
set_property "needs_refresh" "1" $obj
set_property "part" $target_part $obj
set_property "steps.synth_design.tcl.pre" "$script_dir/shared_presynth.tcl" $obj
set_property "steps.synth_design.args.more options" -value "-generic BUILD_DATE=\$TCL_BUILD_DATE" -object $obj
current_run -synthesis [get_runs synth_1]

# Create 'impl_1' run (if not found)
if {[string equal [get_runs -quiet impl_1] ""]} {
  create_run -name impl_1 -part $target_part -flow {Vivado Implementation 2015} -strategy "Vivado Implementation Defaults" -constrset constrs_1 -parent_run synth_1
} else {
  set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]
  set_property flow "Vivado Implementation 2015" [get_runs impl_1]
}
variable obj [get_runs impl_1]
set_property "needs_refresh" "1" $obj
set_property "part" $target_part $obj
set_property "steps.write_bitstream.args.readback_file" "0" $obj
set_property "steps.write_bitstream.args.verbose" "0" $obj
set_property "STEPS.WRITE_BITSTREAM.TCL.POST" "$postbit_script" $obj
current_run -implementation [get_runs impl_1]

# Done!
puts "INFO: Project created!"
