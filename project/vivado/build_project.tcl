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
# This script builds the specified project, passed via command line.
# It is used as part of the Jenkins build-automation pipeline.
#

if {[llength $argv] == 1} {
    set PROJNAME [lindex $argv 0]
} else {
    error "Must specify project! Pass with -tclargs in batch mode or set argv in GUI mode"
}
puts "Building project: $PROJNAME"

open_project ./$PROJNAME/$PROJNAME.xpr
update_compile_order -fileset sources_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
