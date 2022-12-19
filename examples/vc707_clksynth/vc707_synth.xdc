# Copyright 2022 The Aerospace Corporation
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
### Set all I/O pin locations

set_property PACKAGE_PIN AV40   [get_ports {ext_rst_p}];        # CPU_RESET
set_property PACKAGE_PIN E19    [get_ports {sys_clk_p}];        # SYSCLK_P
set_property PACKAGE_PIN AJ32   [get_ports {gpio0_out_p}];      # USER_SMA_CLOCK_P
set_property PACKAGE_PIN AN31   [get_ports {gpio1_out_p}];      # USER_SMA_GPIO_P
set_property PACKAGE_PIN AH8    [get_ports {gtx0_ref_p}];       # SGMIICLK_Q0_P
set_property PACKAGE_PIN AP4    [get_ports {gtx0_out_p}];       # SMA_MGT_TX_P
set_property PACKAGE_PIN AK8    [get_ports {gtx1_ref_p}];       # SMA_MGT_REFCLK_P
set_property PACKAGE_PIN AM4    [get_ports {gtx1_out_p}];       # SFP_TX_P
set_property PACKAGE_PIN AM39   [get_ports {status_led[0]}];    # GPIO_LED_0_LS
set_property PACKAGE_PIN AN39   [get_ports {status_led[1]}];    # GPIO_LED_1_LS
set_property PACKAGE_PIN AR37   [get_ports {status_led[2]}];    # GPIO_LED_2_LS
set_property PACKAGE_PIN AT37   [get_ports {status_led[3]}];    # GPIO_LED_3_LS
set_property PACKAGE_PIN AR35   [get_ports {status_led[4]}];    # GPIO_LED_4_LS
set_property PACKAGE_PIN AP41   [get_ports {status_led[5]}];    # GPIO_LED_5_LS
set_property PACKAGE_PIN AP42   [get_ports {status_led[6]}];    # GPIO_LED_6_LS
set_property PACKAGE_PIN AU39   [get_ports {status_led[7]}];    # GPIO_LED_7_LS

#####################################################################
### Set all voltages and signaling standards

# All single-ended I/O pins at 1.8V
set_property IOSTANDARD LVCMOS18 [get_ports ext_rst_p];
set_property IOSTANDARD LVCMOS18 [get_ports status_led*];

# CFGBVS pin = GND.
set_property CFGBVS GND [current_design];
set_property CONFIG_VOLTAGE 1.8 [current_design];

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################
