# Copyright 2019 The Aerospace Corporation
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

# Synthesis constraints for switch_top_ext_ac701
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

# 125 MHz data clock for Eth0 and Eth3 (from SJA1105 and AR8031)
create_clock -period 8.0 -name clk_eth0 [get_ports uplnk_rxc]
create_clock -period 8.0 -name clk_eth3 [get_ports rgmii_rxc]

# Synthesized clocks
create_clock -period 8.0 -name synth_125a [get_nets clk_125_00]
create_clock -period 8.0 -name synth_125b [get_nets clk_125_90]
create_clock -period 5.0 -name synth_200 [get_nets clk_200]

# Mark all input clocks as mutually asynchronous, including synchronous
# clocks for which we've designed explicit clock-domain-crossings.
# (Same as adding calling set_false_path on all pairwise permutations.)
# See also: https://www.xilinx.com/support/answers/44651.html
set_clock_groups -asynchronous \
    -group [get_clocks clk_ref      -include_generated_clocks] \
    -group [get_clocks clk_eth0     -include_generated_clocks] \
    -group [get_clocks clk_eth3     -include_generated_clocks] \
    -group [get_clocks synth_125a   -include_generated_clocks] \
    -group [get_clocks synth_125b   -include_generated_clocks] \
    -group [get_clocks synth_200    -include_generated_clocks]
