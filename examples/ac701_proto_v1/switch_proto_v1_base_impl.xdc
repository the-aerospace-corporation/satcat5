# Copyright 2021-2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Synthesis constraints for switch_top_baseline
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

# 25 MHz clock reference (from SJA1105)
create_clock -period 40.0 -name clk_ref [get_ports sja_clk25]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {sja_clk25_IBUF}]

# 50 MHz data clock for Eth0 (from SJA1105)
create_clock -period 20.0 -name clk_eth0 [get_ports rmii_clkin]

# Mark all input clocks as mutually asynchronous.
# (Same as adding calling set_false_path on all pairwise permutations.)
# See also: https://www.xilinx.com/support/answers/44651.html
set_clock_groups -asynchronous \
    -group [get_clocks clk_ref      -include_generated_clocks] \
    -group [get_clocks clk_eth0     -include_generated_clocks]

# Explicit delay constraints on clock-crossing signals.
set_max_delay -datapath_only 5.0 -from [get_cells -hier -filter {satcat5_cross_clock_src > 0}]
set_max_delay -datapath_only 5.0 -to   [get_cells -hier -filter {satcat5_cross_clock_dst > 0}]
