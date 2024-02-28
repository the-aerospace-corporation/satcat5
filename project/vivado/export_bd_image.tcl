# ------------------------------------------------------------------------
# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script open a Vivado project, finds all Vivado block designs (*.bd),
# and exports each one as a PDF or SVG file.
#
# The difficulty is that the "write_bd_layout" command can only be run if
# Vivado is in GUI mode.  If this script is called from a console mode, it
# will automatically launch a new Vivado GUI to export the images and exit.
#

puts {Running export_bd_image.tcl}

# Open the specified block design and export an image of same name.
proc export_bd_image_one { bd_file } {
    variable out_path [get_property DIRECTORY [current_project]]
    variable out_name [file rootname [file tail $bd_file]]
    # Clear output files from previous runs.
    file delete $out_path/$out_name.pdf
    file delete $out_path/$out_name.svg
    # Open block diagram and attempt to export image files.
    variable bd_obj [open_bd_design $bd_file]
    write_bd_layout -force -format pdf $out_path/$out_name.pdf
    write_bd_layout -force -format svg $out_path/$out_name.svg
    close_bd_design $bd_obj
    # Were the image files created successfully?
    variable ok_pdf [file exist $out_path/$out_name.pdf]
    variable ok_svg [file exist $out_path/$out_name.svg]
    return [expr $ok_pdf && $ok_svg]
}

# Call "export_bd_image_one" for every .bd file in the current project.
proc export_bd_image_all {} {
    variable all_ok 1
    foreach bd [get_files *.bd] {
        variable ok [export_bd_image_one $bd]
        variable all_ok [expr $all_ok && $ok] 
    }
    return $all_ok
}

# Launch a new Vivado instance to process the current project.
proc launch_nested_gui {} {
    variable this_script [file normalize [info script]]
    variable proj_dir [get_property DIRECTORY [current_project]]
    variable proj_xpr [file normalize $proj_dir/[current_project].xpr]
    exec vivado -mode gui -source "$this_script" -tclargs "$proj_xpr"
}

# What is the current script context?
if {[current_project -quiet] == ""} {
    # No project open --> Must be the newly-launched GUI.
    # First command-line argument should be the filename to be opened.
    if {$argc > 0} {
        open_project [lindex $argv 0]
        export_bd_image_all
        exit 0
    } else {
        error {No project opened and no project path specified.}
    }
} elseif {[llength [get_files *.bd]] > 0} {
    # Project is open and there are BD files.
    # Attempt export; if that fails, launch a GUI and try again.
    if {[export_bd_image_all]} {
        puts {Image export successful.}
    } else {
        puts {Launching GUI for image export...}
        launch_nested_gui
    }
} else {
    error {Current project has no block design files.}
}

puts {Finished export_bd_image.tcl} 
