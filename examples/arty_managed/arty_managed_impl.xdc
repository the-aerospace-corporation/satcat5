# Copyright 2021-2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Implemenation constraints for arty_managed
# This file is for added constraints required ONLY during implementation.

#####################################################################
### Bitstream generation

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design];
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design];
set_property CONFIG_MODE SPIx4 [current_design];


#####################################################################
### Timing constraints

# 100 MHz clock reference
create_clock -period 10.000 -name clk_ref [get_ports ext_clk100];

# Mark all input clocks as mutually asynchronous, including synchronous
# clocks for which we've designed explicit clock-domain-crossings.
# (Same as adding calling set_false_path on all pairwise permutations.)
# See also: https://www.xilinx.com/support/answers/44651.html
set_clock_groups -asynchronous -group [get_clocks clk_ref -include_generated_clocks];

# Explicit delay constraints on clock-crossing signals.
set_max_delay -datapath_only 5.0 -from [get_cells -hier -filter {satcat5_cross_clock_src > 0}]
set_max_delay -datapath_only 5.0 -to   [get_cells -hier -filter {satcat5_cross_clock_dst > 0}]
