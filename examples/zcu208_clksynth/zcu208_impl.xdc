# Copyright 2023 The Aerospace Corporation
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

#####################################################################
### Bitstream generation

#####################################################################
### Timing constraints

# Input clocks at 100, 125, and 400 MHz
create_clock -period 10.000 -name clk_100 [get_ports clk_100_p];
create_clock -period  8.000 -name clk_125 [get_ports clk_125_p];
create_clock -period  2.500 -name clk_400 [get_ports refclk_in_p];

# Mark all input clocks as mutually asynchronous, including synchronous
# clocks for which we've designed explicit clock-domain-crossings.
# (Same as adding calling set_false_path on all pairwise permutations.)
# See also: https://www.xilinx.com/support/answers/44651.html
set_clock_groups -asynchronous \
    -group [get_clocks clk_100 -include_generated_clocks] \
    -group [get_clocks clk_125 -include_generated_clocks] \
    -group [get_clocks clk_400 -include_generated_clocks] \
    -group [get_clocks RFADC0_CLK -include_generated_clocks] \
    -group [get_clocks RFADC1_CLK -include_generated_clocks] \
    -group [get_clocks RFADC2_CLK -include_generated_clocks] \
    -group [get_clocks RFADC3_CLK -include_generated_clocks] \
    -group [get_clocks RFDAC0_CLK -include_generated_clocks] \
    -group [get_clocks RFDAC1_CLK -include_generated_clocks] \
    -group [get_clocks RFDAC2_CLK -include_generated_clocks] \
    -group [get_clocks RFDAC3_CLK -include_generated_clocks];

# Explicit delay constraints on clock-crossing signals.
set_max_delay -datapath_only 5.0 -from [get_cells -hier -filter {satcat5_cross_clock_src > 0}]
set_max_delay -datapath_only 5.0 -to   [get_cells -hier -filter {satcat5_cross_clock_dst > 0}]
set_max_delay -datapath_only 5.0 -from [get_cells {u_vref/u_ctr/tstamp*[*]}]
