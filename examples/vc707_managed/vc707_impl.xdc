# Copyright 2021-2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Implementation constraints for vc707_managed
# This file is for added constraints required ONLY during implementation.

#####################################################################
### Bitstream generation

set_property BITSTREAM.CONFIG.BPI_SYNC_MODE DISABLE [current_design];
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design];
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE [current_design];
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design];
set_property CONFIG_MODE BPI16 [current_design];

#####################################################################
### Timing constraints

# Input clocks at 80 and 125 MHz.
# (200 MHz SYSCLK is defined by MIG constraints)
create_clock -period 12.500 -name clk_emc [get_ports emc_clk];
create_clock -period 8.000 -name clk_mgt [get_ports mgt_clk_clk_p];

# Mark all input clocks as mutually asynchronous, including synchronous
# clocks for which we've designed explicit clock-domain-crossings.
# (Same as adding calling set_false_path on all pairwise permutations.)
# See also: https://www.xilinx.com/support/answers/44651.html
set_clock_groups -asynchronous \
    -group [get_clocks clk_emc -include_generated_clocks] \
    -group [get_clocks clk_mgt -include_generated_clocks] \
    -group [get_clocks *gtxe2* -include_generated_clocks] \
    -group [get_clocks sys_clk_clk_p -include_generated_clocks];

# Explicit delay constraints on clock-crossing signals.
set_max_delay -datapath_only 5.0 -from [get_cells -hier -filter {satcat5_cross_clock_src > 0}]
set_max_delay -datapath_only 5.0 -to   [get_cells -hier -filter {satcat5_cross_clock_dst > 0}]
