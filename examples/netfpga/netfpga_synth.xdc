# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Synthesis constraints for "netfpga" example design.
# Define pin locations and I/O standards only.

#####################################################################
### Set all I/O pin locations

set_property PACKAGE_PIN AA3    [get_ports {system_clk_clk_p}]; # 200 MHz LVDS clock
set_property PACKAGE_PIN AA2    [get_ports {system_clk_clk_n}];
set_property PACKAGE_PIN AA8    [get_ports {system_rst}];       # "Reset" button (BTN4)
set_property PACKAGE_PIN V13    [get_ports {mdio_sck}];         # Shared MDIO (all PHYs)
set_property PACKAGE_PIN W13    [get_ports {mdio_sda}];
set_property PACKAGE_PIN E17    [get_ports {leds[0]}];          # Status LEDs
set_property PACKAGE_PIN AF14   [get_ports {leds[1]}];
set_property PACKAGE_PIN F17    [get_ports {leds[2]}];
set_property PACKAGE_PIN W19    [get_ports {leds[3]}];

set_property PACKAGE_PIN D19    [get_ports {pmod_ja[0]}];       # PMOD-JA (pins 1-4 only)
set_property PACKAGE_PIN E23    [get_ports {pmod_ja[1]}];
set_property PACKAGE_PIN D25    [get_ports {pmod_ja[2]}];
set_property PACKAGE_PIN F23    [get_ports {pmod_ja[3]}];

set_property PACKAGE_PIN F20    [get_ports {pmod_jb[0]}];       # PMOD-JB (pins 1-4 only)
set_property PACKAGE_PIN E15    [get_ports {pmod_jb[1]}];
set_property PACKAGE_PIN H18    [get_ports {pmod_jb[2]}];
set_property PACKAGE_PIN G19    [get_ports {pmod_jb[3]}];

set_property PACKAGE_PIN B9     [get_ports {rgmii0_txc}];       # RGMII1 interface
set_property PACKAGE_PIN H8     [get_ports {rgmii0_tx_ctl}];
set_property PACKAGE_PIN A8     [get_ports {rgmii0_td[0]}];
set_property PACKAGE_PIN D8     [get_ports {rgmii0_td[1]}];
set_property PACKAGE_PIN G9     [get_ports {rgmii0_td[2]}];
set_property PACKAGE_PIN H9     [get_ports {rgmii0_td[3]}];
set_property PACKAGE_PIN E10    [get_ports {rgmii0_rxc}];
set_property PACKAGE_PIN B12    [get_ports {rgmii0_rx_ctl}];
set_property PACKAGE_PIN B11    [get_ports {rgmii0_rd[0]}];
set_property PACKAGE_PIN A10    [get_ports {rgmii0_rd[1]}];
set_property PACKAGE_PIN B10    [get_ports {rgmii0_rd[2]}];
set_property PACKAGE_PIN A9     [get_ports {rgmii0_rd[3]}];
set_property PACKAGE_PIN D18    [get_ports {rgmii0_rstn}];

set_property PACKAGE_PIN J10    [get_ports {rgmii1_txc}];       # RGMII2 interface
set_property PACKAGE_PIN F8     [get_ports {rgmii1_tx_ctl}];
set_property PACKAGE_PIN D10    [get_ports {rgmii1_td[0]}];
set_property PACKAGE_PIN G10    [get_ports {rgmii1_td[1]}];
set_property PACKAGE_PIN D9     [get_ports {rgmii1_td[2]}];
set_property PACKAGE_PIN F9     [get_ports {rgmii1_td[3]}];
set_property PACKAGE_PIN C12    [get_ports {rgmii1_rxc}];
set_property PACKAGE_PIN A12    [get_ports {rgmii1_rx_ctl}];
set_property PACKAGE_PIN A13    [get_ports {rgmii1_rd[0]}];
set_property PACKAGE_PIN C9     [get_ports {rgmii1_rd[1]}];
set_property PACKAGE_PIN D11    [get_ports {rgmii1_rd[2]}];
set_property PACKAGE_PIN C11    [get_ports {rgmii1_rd[3]}];
set_property PACKAGE_PIN E25    [get_ports {rgmii1_rstn}];

set_property PACKAGE_PIN E13    [get_ports {rgmii2_txc}];       # RGMII3 interface
set_property PACKAGE_PIN F10    [get_ports {rgmii2_tx_ctl}];
set_property PACKAGE_PIN G12    [get_ports {rgmii2_td[0]}];
set_property PACKAGE_PIN F13    [get_ports {rgmii2_td[1]}];
set_property PACKAGE_PIN F12    [get_ports {rgmii2_td[2]}];
set_property PACKAGE_PIN H11    [get_ports {rgmii2_td[3]}];
set_property PACKAGE_PIN E11    [get_ports {rgmii2_rxc}];
set_property PACKAGE_PIN C13    [get_ports {rgmii2_rx_ctl}];
set_property PACKAGE_PIN A14    [get_ports {rgmii2_rd[0]}];
set_property PACKAGE_PIN B14    [get_ports {rgmii2_rd[1]}];
set_property PACKAGE_PIN E12    [get_ports {rgmii2_rd[2]}];
set_property PACKAGE_PIN D13    [get_ports {rgmii2_rd[3]}];
set_property PACKAGE_PIN K21    [get_ports {rgmii2_rstn}];

set_property PACKAGE_PIN D14    [get_ports {rgmii3_txc}];       # RGMII4 interface
set_property PACKAGE_PIN J11    [get_ports {rgmii3_tx_ctl}];
set_property PACKAGE_PIN J13    [get_ports {rgmii3_td[0]}];
set_property PACKAGE_PIN G14    [get_ports {rgmii3_td[1]}];
set_property PACKAGE_PIN H14    [get_ports {rgmii3_td[2]}];
set_property PACKAGE_PIN H13    [get_ports {rgmii3_td[3]}];
set_property PACKAGE_PIN G11    [get_ports {rgmii3_rxc}];
set_property PACKAGE_PIN A15    [get_ports {rgmii3_rx_ctl}];
set_property PACKAGE_PIN B15    [get_ports {rgmii3_rd[0]}];
set_property PACKAGE_PIN F14    [get_ports {rgmii3_rd[1]}];
set_property PACKAGE_PIN C14    [get_ports {rgmii3_rd[2]}];
set_property PACKAGE_PIN H12    [get_ports {rgmii3_rd[3]}];
set_property PACKAGE_PIN L23    [get_ports {rgmii3_rstn}];

#####################################################################
### Set all voltages and signaling standards

set_property IOSTANDARD LVDS     [get_ports {system_clk*}];
set_property IOSTANDARD LVCMOS18 [get_ports {system_rst}];
set_property IOSTANDARD LVCMOS18 [get_ports {mdio_*}];
set_property IOSTANDARD LVCMOS33 [get_ports {leds[0]}];
set_property IOSTANDARD LVCMOS18 [get_ports {leds[1]}];
set_property IOSTANDARD LVCMOS33 [get_ports {leds[2]}];
set_property IOSTANDARD LVCMOS18 [get_ports {leds[3]}];
set_property IOSTANDARD LVCMOS33 [get_ports {pmod*}];
set_property IOSTANDARD LVCMOS18 [get_ports {rgmii*}];          # All RGMII pins 1.8V
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii*_rstn}];     # ...except the reset

set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################
