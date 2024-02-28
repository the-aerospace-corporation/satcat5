# ------------------------------------------------------------------------
# Copyright 2022-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This file defines TCL helper functions for building the currently open
# project, finding errors in out-of-context runs, writing .bit and .bin
# files, and other tasks relating to Vivado builds.
#
# It does not take any action when run; it only defines TCL procedures
# for use by other scripts.
#

puts {Loading shared_build.tcl}

# Launch the specified run and wait for it to complete.
# If it fails, print some information about why.
proc satcat5_launch_run { {name impl_1} {step write_bitstream} } {
    # Attempt to start run and any prerequisites
    # Note: Ignore "launch_runs" errors for already-finished builds.
    catch {launch_runs $name -to_step $step -jobs 4}
    wait_on_run $name
    # If the run failed, print some information about why.
    if {[get_property PROGRESS [get_runs $name]] != "100%"} {
        satcat5_scan_logs
        error "ERROR: $name failed. See logs above for details."
    }
}

# Scan "runme.log" files from all runs and out-of-context runs.
# (Vivado is not good about printing errors in out-of-context runs.)
proc satcat5_scan_logs {} {
    puts {Log scan starting...}
    variable proj_dir [get_property DIRECTORY [current_project]]
    foreach log_file [glob "${proj_dir}/*/*/runme.log"] {
        # Read the file contents...
        puts "Reading ${log_file}..."
        variable log_fd [open "$log_file"]
        variable log_data [read $log_fd]
        close $log_fd
        # Iterate through each line...
        foreach line [split "$log_data" "\n"] {
            variable is_err [string match "ERROR:*" $line]
            variable is_crw [string match "CRITICAL WARNING:*" $line]
            if { $is_err || $is_crw} {puts "$line"}
        }
    }
    puts {Log scan completed.}
}

# Write SYSDEF file (*.hdf) including bitfile and Microblaze metadata.
proc satcat5_write_hdf { outfile } {
    # Find the generated .bit file for this project.
    puts {Looking for output files...}
    variable run_dir [get_property DIRECTORY [current_run]]
    variable run_bit [lindex [glob -nocomplain $run_dir/*.bit] 0]
    variable run_mmi [lindex [glob -nocomplain $run_dir/*.mmi] 0]

    if {$run_bit == ""} {error "Bitfile generation failed: Missing .BIT file."}
    if {$run_mmi == ""} {error "Bitfile generation failed: Missing .MMI file."}

    # Derived filenames. Note "outfile" may or may not include extension.
    variable run_hwd [file rootname "$run_bit"].hwdef
    variable out_hdf [file rootname "$outfile"].hdf

    # Write out the hardware definition
    puts "Writing SYSDEF:"
    puts "    BIT: $run_bit"
    puts "    MMI: $run_mmi"

    write_hwdef -force -file "$run_hwd"
    write_sysdef -force \
        -hwdef "$run_hwd" \
        -bitfile "$run_bit" \
        -meminfo "$run_mmi" \
        -file "$out_hdf"

    variable sysdef_size [file size "$out_hdf"]
    puts "SYSDEF Ready ($sysdef_size bytes)"
}

# Write PROM file (*.bin) suitable for booting FPGA.
proc satcat5_write_bin { outfile {interface SPIx4} {size 16} } {
    # Find the generated .bit file for this projects.
    puts {Looking for output files...}
    variable run_dir [get_property DIRECTORY [current_run]]
    variable run_bit [lindex [glob -nocomplain $run_dir/*.bit] 0]

    if {"$run_bit" == ""} {error "Bitfile generation failed: Missing .BIT file."}

    # Derived filenames. Note "outfile" may or may not include extension.
    variable out_bin [file rootname "$outfile"].bin

    # Write out the corresponding .bin file.
    write_cfgmem -force -format BIN \
        -interface $interface \
        -size $size \
        -loadbit "up 0x0 ${run_bit}" \
        "${out_bin}"
}
