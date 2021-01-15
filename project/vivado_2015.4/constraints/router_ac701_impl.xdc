# Copyright 2020 The Aerospace Corporation
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
