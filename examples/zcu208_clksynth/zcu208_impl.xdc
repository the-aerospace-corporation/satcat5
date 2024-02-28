# Copyright 2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

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
