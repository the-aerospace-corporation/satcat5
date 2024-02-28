# Copyright 2021-2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

#####################################################################
### Bitstream generation

set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN DIV-2 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

#####################################################################
### Timing constraints

# 90 MHz EMC-Clock
create_clock -period 11.1 -name clk_emc [get_ports scrub_clk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {scrub_clk*}]

# 125 MHz Rx clock for each RGMII port.
create_clock -period 8.0 -name clk_eth0 [get_ports rgmii0_rxc]
create_clock -period 8.0 -name clk_eth1 [get_ports rgmii1_rxc]
create_clock -period 8.0 -name clk_eth2 [get_ports rgmii2_rxc]

# 200 MHz SYSCLK is specified by the Clock Generator IP-Core.
# (Fetch it rather than overwriting with a new one.)
set clk_sys [get_clocks -of_objects [get_ports refclk200_clk_p]]

# Mark all input clocks as mutually asynchronous, including synchronous
# clocks for which we've designed explicit clock-domain-crossings.
# (Same as adding calling set_false_path on all pairwise permutations.)
# See also: https://www.xilinx.com/support/answers/44651.html
set_clock_groups -asynchronous \
    -group [get_clocks clk_emc      -include_generated_clocks] \
    -group [get_clocks clk_eth0     -include_generated_clocks] \
    -group [get_clocks clk_eth1     -include_generated_clocks] \
    -group [get_clocks clk_eth2     -include_generated_clocks] \
    -group [get_clocks $clk_sys     -include_generated_clocks]

# Explicit delay constraints on clock-crossing signals.
set_max_delay -datapath_only 5.0 -from [get_cells -hier -filter {satcat5_cross_clock_src > 0}]
set_max_delay -datapath_only 5.0 -to   [get_cells -hier -filter {satcat5_cross_clock_dst > 0}]
