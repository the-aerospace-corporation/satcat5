# ------------------------------------------------------------------------
# Copyright 2021-2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script checks if the SatCat5 IP-cores are already installed
# in the project search path.  If not, it creates them.

puts {Running shared_ipcores.tcl}

# Count IP-cores with "satcat5" in the name.
update_ip_catalog -quiet
variable ipcount [llength [get_ipdefs *satcat5*]]
if {$ipcount eq 0} {
    # No cores detected, run the installation script.
    puts "Installing SatCat5 IP-cores."
    variable script_dir [file normalize [file dirname [info script]]]
    source $script_dir/create_all_ipcores.tcl
    # Refresh the count after installation.
    update_ip_catalog
    set ipcount [llength [get_ipdefs *satcat5*]]
}
puts "Found $ipcount SatCat5 IP-cores."
