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
# This script checks if the SatCat5 IP-cores are already installed
# at "./ipcores".  If not, it creates them.

puts {Running shared_ipcores.tcl}

# Set $script_dir if it doesn't already exist.
if {![info exists script_dir]} {
    set script_dir [file normalize [file dirname [info script]]]
}

# Add the folder where the SatCat5 cores should be installed.
set_property ip_repo_paths [file normalize $script_dir/ipcores] [current_project]
update_ip_catalog

# If the cores don't already exist, create them now.
set ipcount [llength [get_ipdefs *satcat5*]]
if {$ipcount eq 0} {
    puts "Installing SatCat5 IP-cores."
    source $script_dir/create_all_ipcores.tcl
} else {
    puts "Found $ipcount SatCat5 IP-cores."
}
