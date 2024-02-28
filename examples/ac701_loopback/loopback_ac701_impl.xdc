# Copyright 2021-2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

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

# Explicit delay constraints on clock-crossing signals.
set_max_delay -datapath_only 5.0 -from [get_cells -hier -filter {satcat5_cross_clock_src > 0}]
set_max_delay -datapath_only 5.0 -to   [get_cells -hier -filter {satcat5_cross_clock_dst > 0}]
set_max_delay 1.5 -from synth_625a -to synth_125  -datapath_only
set_max_delay 1.5 -from synth_125  -to synth_625a -datapath_only

