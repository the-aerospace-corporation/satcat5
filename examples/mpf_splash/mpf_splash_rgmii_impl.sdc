##########################################################################
## Copyright 2021 The Aerospace Corporation.
## This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
##########################################################################

# Timing Constraints

create_clock -name {REF_CLK_50MHZ} -period 20 [ get_ports { REF_CLK_50MHZ } ]
create_clock -name {uplnk_rxc}     -period  8 [ get_ports { uplnk_rxc } ]

# Manually include clock constraints for u_clkgen/u_ccc since these are apparently not inferred or detected in their generated file
create_clock           -name {pll_refclk} -period 20                          [ get_pins { u_clkgen/u_ccc/PF_CCC_C1_0/pll_inst_0/REF_CLK_0 } ]
create_generated_clock -name {clk_200_00} -multiply_by 4              -source [ get_pins { u_clkgen/u_ccc/PF_CCC_C1_0/pll_inst_0/REF_CLK_0 } ] -phase  0 [ get_pins { u_clkgen/u_ccc/PF_CCC_C1_0/pll_inst_0/OUT0 } ]
create_generated_clock -name {clk_125_00} -multiply_by 5 -divide_by 2 -source [ get_pins { u_clkgen/u_ccc/PF_CCC_C1_0/pll_inst_0/REF_CLK_0 } ] -phase  0 [ get_pins { u_clkgen/u_ccc/PF_CCC_C1_0/pll_inst_0/OUT1 } ]
create_generated_clock -name {clk_125_90} -multiply_by 5 -divide_by 2 -source [ get_pins { u_clkgen/u_ccc/PF_CCC_C1_0/pll_inst_0/REF_CLK_0 } ] -phase 90 [ get_pins { u_clkgen/u_ccc/PF_CCC_C1_0/pll_inst_0/OUT2 } ]

# Mark all input clocks as mutually asynchronous, including synchronous
# clocks for which we've designed explicit clock-domain-crossings.
set_clock_groups -name {clkgroup} -asynchronous \
    -group [get_clocks REF_CLK_50MHZ] \
    -group [get_clocks uplnk_rxc    ] \
    -group [get_clocks pll_refclk   ] \
    -group [get_clocks clk_200_00   ] \
    -group [get_clocks clk_125_00   ] \
    -group [get_clocks clk_125_90   ]


# Set input delays for RGMII RX. uplnk_rxc is delayed 2ns at PHY to appear in data center
# We give 1.5ns before and after the edge
set_input_delay -clock [get_clocks {uplnk_rxc}] -min 1.2 [get_ports {uplnk_rxctl}]
set_input_delay -clock [get_clocks {uplnk_rxc}] -max 2.8 [get_ports {uplnk_rxctl}]
set_input_delay -clock [get_clocks {uplnk_rxc}] -clock_fall -min -add_delay 1.2 [get_ports {uplnk_rxctl}]
set_input_delay -clock [get_clocks {uplnk_rxc}] -clock_fall -max -add_delay 2.8 [get_ports {uplnk_rxctl}]

set_input_delay -clock [get_clocks {uplnk_rxc}] -min 1.2 [get_ports {uplnk_rxd[*]}]
set_input_delay -clock [get_clocks {uplnk_rxc}] -max 2.8 [get_ports {uplnk_rxd[*]}]
set_input_delay -clock [get_clocks {uplnk_rxc}] -clock_fall -min -add_delay 1.2 [get_ports {uplnk_rxd[*]}]
set_input_delay -clock [get_clocks {uplnk_rxc}] -clock_fall -max -add_delay 2.8 [get_ports {uplnk_rxd[*]}]
