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

puts {Running shared_presynth.tcl}

# Disable multi-threading during synthesis, which is unstable in Vivado 2015.4.
# See also: https://forums.xilinx.com/t5/Welcome-Join/Vivado-Crashing-during-synthesis-after-upgrading-to-2015-4/td-p/678413
set_param synth.elaboration.rodinMoreOptions "set rt::enableParallelFlowOnWindows 0"

# Get current time...
set time_now [clock seconds]

# And set the build-date parameter to a user-readable string.
# (This is passed to the main design as a generic.)
set TCL_BUILD_DATE [clock format $time_now -format %Y-%m-%d@%H:%M]
