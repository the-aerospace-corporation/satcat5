# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------

puts {Running shared_presynth.tcl}

# Disable multi-threading during synthesis, which is unstable in Vivado 2015.4.
# See also: https://forums.xilinx.com/t5/Welcome-Join/Vivado-Crashing-during-synthesis-after-upgrading-to-2015-4/td-p/678413
set_param synth.elaboration.rodinMoreOptions "set rt::enableParallelFlowOnWindows 0"

# Get current time...
set time_now [clock seconds]

# And set the build-date parameter to a user-readable string.
# (This is passed to the main design as a generic.)
set TCL_BUILD_DATE [clock format $time_now -format %Y-%m-%d@%H:%M]
