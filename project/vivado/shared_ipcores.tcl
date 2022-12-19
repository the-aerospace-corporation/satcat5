# ------------------------------------------------------------------------
# Copyright 2021, 2022 The Aerospace Corporation
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
