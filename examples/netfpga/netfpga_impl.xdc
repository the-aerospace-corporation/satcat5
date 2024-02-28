# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Implementation constraints for "netfpga" example design.
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

# Each RGMII port has a 125 MHz input clock.
create_clock -period 8.000 -name clk_rgmii0 [get_ports rgmii0_rxc];
create_clock -period 8.000 -name clk_rgmii1 [get_ports rgmii1_rxc];
create_clock -period 8.000 -name clk_rgmii2 [get_ports rgmii2_rxc];
create_clock -period 8.000 -name clk_rgmii3 [get_ports rgmii3_rxc];

# Define the 200 MHz system clock.
# TODO: Why isn't this being defined by the MIG constraints?
create_clock -period 5.000 -name clk_system [get_ports system_clk_clk_p]

# Mark all input clocks as mutually asynchronous, including synchronous
# clocks for which we've designed explicit clock-domain-crossings.
# (Same as adding calling set_false_path on all pairwise permutations.)
# See also: https://www.xilinx.com/support/answers/44651.html
set_clock_groups -asynchronous \
    -group [get_clocks clk_out1_netfpga_clk_wiz_1_0 -include_generated_clocks] \
    -group [get_clocks clk_out2_netfpga_clk_wiz_1_0 -include_generated_clocks] \
    -group [get_clocks clk_rgmii0 -include_generated_clocks] \
    -group [get_clocks clk_rgmii1 -include_generated_clocks] \
    -group [get_clocks clk_rgmii2 -include_generated_clocks] \
    -group [get_clocks clk_rgmii3 -include_generated_clocks] \
    -group [get_clocks clk_system -include_generated_clocks] \
    -group [get_clocks mmcm_clkout0 -include_generated_clocks];

# Explicit delay constraints on clock-crossing signals.
set_max_delay -datapath_only 5.0 -from [get_cells -hier -filter {satcat5_cross_clock_src > 0}]
set_max_delay -datapath_only 5.0 -to   [get_cells -hier -filter {satcat5_cross_clock_dst > 0}]
