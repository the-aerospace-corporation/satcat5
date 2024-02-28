# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

#####################################################################
### Bitstream generation

set_property BITSTREAM.CONFIG.BPI_SYNC_MODE DISABLE [current_design];
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design];
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE [current_design];
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design];
set_property CONFIG_MODE BPI16 [current_design];

#####################################################################
### Timing constraints

# Input clocks at 200 and 125 MHz.
create_clock -period 8.000 -name clk_gtx0 [get_ports gtx0_ref_p];
create_clock -period 8.000 -name clk_gtx1 [get_ports gtx1_ref_p];
create_clock -period 5.000 -name clk_sys [get_ports sys_clk_p];

# Mark all input clocks as mutually asynchronous, including synchronous
# clocks for which we've designed explicit clock-domain-crossings.
# (Same as adding calling set_false_path on all pairwise permutations.)
# See also: https://www.xilinx.com/support/answers/44651.html
set_clock_groups -asynchronous \
    -group [get_clocks clk_gtx0 -include_generated_clocks] \
    -group [get_clocks clk_gtx1 -include_generated_clocks] \
    -group [get_clocks clk_sys -include_generated_clocks];

# Explicit delay constraints on clock-crossing signals.
set_max_delay -datapath_only 5.0 -from [get_cells -hier -filter {satcat5_cross_clock_src > 0}]
set_max_delay -datapath_only 5.0 -to   [get_cells -hier -filter {satcat5_cross_clock_dst > 0}]
