# Copyright 2020 The Aerospace Corporation
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

# Implementation constraints for "loopback_ac701"
# This file is for added constraints required ONLY during implementation.

#####################################################################
### Bitstream generation

set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN DIV-2 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

#####################################################################
### Timing constraints

# 200 MHz system clock references
create_clock -period 5.0 -name clk_ext [get_ports ext_clk200*]

# Synthesized clocks
create_clock -period 8.0 -name synth_125 [get_nets clk_125]
create_clock -period 5.0 -name synth_200 [get_nets clk_200]
create_clock -period 1.6 -name synth_625a [get_nets clk_625_00]
create_clock -period 1.6 -name synth_625b [get_nets clk_625_90]

# Mark most input clocks as mutually asynchronous, including synchronous
# clocks for which we've designed explicit clock-domain-crossings.
# (Same as adding calling set_false_path on all pairwise permutations.)
# See also: https://www.xilinx.com/support/answers/44651.html
set_clock_groups -asynchronous \
    -group [get_clocks clk_ext      -include_generated_clocks] \
    -group [get_clocks synth_125    -include_generated_clocks] \
    -group [get_clocks synth_200    -include_generated_clocks] \
    -group [get_clocks synth_625a   -include_generated_clocks] \
    -group [get_clocks synth_625b   -include_generated_clocks]

# Max-delay constraint on specific cross-clock paths.
set_max_delay 1.5 -from synth_625a -to synth_125  -datapath_only
set_max_delay 1.5 -from synth_125  -to synth_625a -datapath_only
