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

# Synthesis constraints for switch_top_baseline
# Define pin locations and I/O standards only.

#####################################################################
### Set all I/O pin locations

# Eth0 = Uplink RMII interface.
set_property PACKAGE_PIN G15    [get_ports {rmii_rxd[0]}];      # FMC_LA05P = ETH0_TX_D0
set_property PACKAGE_PIN F15    [get_ports {rmii_rxd[1]}];      # FMC_LA05N = ETH0_TX_D1
set_property PACKAGE_PIN B20    [get_ports {rmii_rxen}];        # FMC_LA13P = ETH0_TX_EN
set_property PACKAGE_PIN A20    [get_ports {rmii_rxer}];        # FMC_LA13N = ETH0_TX_ER
set_property PACKAGE_PIN K20    [get_ports {rmii_txd[0]}];      # FMC_LA23P = ETH0_RX_D0
set_property PACKAGE_PIN J20    [get_ports {rmii_txd[1]}];      # FMC_LA23N = ETH0_RX_D1
set_property PACKAGE_PIN F23    [get_ports {rmii_txer}];        # FMC_LA27P = ETH0_RX_ER
set_property PACKAGE_PIN E23    [get_ports {rmii_txen}];        # FMC_LA27N = ETH0_RX_DV
set_property PACKAGE_PIN E17    [get_ports {rmii_clkin}];       # FMC_LA01P = ETH0_TX_CLK

# PMOD1 = EoS-Auto (SPI/UART)
set_property PACKAGE_PIN F24    [get_ports {eos_pmod1[0]}];     # FMC_LA29N = PMOD1_IO1
set_property PACKAGE_PIN E26    [get_ports {eos_pmod2[0]}];     # FMC_LA31P = PMOD1_IO2
set_property PACKAGE_PIN D26    [get_ports {eos_pmod3[0]}];     # FMC_LA31N = PMOD1_IO3
set_property PACKAGE_PIN E18    [get_ports {eos_pmod4[0]}];     # FMC_LA01N = PMOD1_IO4

# PMOD2 = EoS-Auto (SPI/UART)
set_property PACKAGE_PIN G25    [get_ports {eos_pmod1[1]}];     # FMC_LA33P = PMOD2_IO1
set_property PACKAGE_PIN F25    [get_ports {eos_pmod2[1]}];     # FMC_LA33N = PMOD2_IO2
set_property PACKAGE_PIN H26    [get_ports {eos_pmod3[1]}];     # FMC_LA32P = PMOD2_IO3
set_property PACKAGE_PIN J21    [get_ports {eos_pmod4[1]}];     # FMC_LA17N = PMOD2_IO4

# PMOD3 = EoS-Auto (SPI/UART)
set_property PACKAGE_PIN AF24   [get_ports {eos_pmod1[2]}];     # FMC_HA04P = PMOD3_IO1
set_property PACKAGE_PIN AF25   [get_ports {eos_pmod2[2]}];     # FMC_HA04N = PMOD3_IO2
set_property PACKAGE_PIN AD21   [get_ports {eos_pmod3[2]}];     # FMC_HA08P = PMOD3_IO3
set_property PACKAGE_PIN AA19   [get_ports {eos_pmod4[2]}];     # FMC_HA00P = PMOD3_IO4

# PMOD4 = EoS-Auto (SPI/UART)
set_property PACKAGE_PIN AE21   [get_ports {eos_pmod1[3]}];     # FMC_HA08N = PMOD4_IO1
set_property PACKAGE_PIN AC19   [get_ports {eos_pmod2[3]}];     # FMC_HA12P = PMOD4_IO2
set_property PACKAGE_PIN AD19   [get_ports {eos_pmod3[3]}];     # FMC_HA12N = PMOD4_IO3
set_property PACKAGE_PIN AB19   [get_ports {eos_pmod4[3]}];     # FMC_HA00N = PMOD4_IO4

# Interface-board control.
set_property PACKAGE_PIN G21    [get_ports {sja_clk25}];        # FMC_LA18N = SWITCH_CLK_OUT
set_property PACKAGE_PIN F20    [get_ports {sja_rstn}];         # FMC_LA06N = SWITCH_nRST
set_property PACKAGE_PIN B21    [get_ports {sja_csb}];          # FMC_LA14N = SWITCH_CTRL_nSS
set_property PACKAGE_PIN A17    [get_ports {sja_sck}];          # FMC_LA10P = SWITCH_CTRL_SCK
set_property PACKAGE_PIN A18    [get_ports {sja_sdo}];          # FMC_LA10N = SWITCH_CTRL_SDI
set_property PACKAGE_PIN H14    [get_ports {mdio_data[0]}];     # FMC_LA02P = ETH1_MDIO
set_property PACKAGE_PIN H15    [get_ports {mdio_clk[0]}];      # FMC_LA02N = ETH1_MDC
set_property PACKAGE_PIN A19    [get_ports {mdio_data[1]}];     # FMC_LA11N = ETH2_MDIO
set_property PACKAGE_PIN B22    [get_ports {mdio_clk[1]}];      # FMC_LA15P = ETH2_MDC
set_property PACKAGE_PIN L17    [get_ports {mdio_data[2]}];     # FMC_LA22P = ETH3_MDIO
set_property PACKAGE_PIN L18    [get_ports {mdio_clk[2]}];      # FMC_LA22N = ETH3_MDC
set_property PACKAGE_PIN F19    [get_ports {eth1_rstn}];        # FMC_LA04N = ETH1_RST_N
set_property PACKAGE_PIN H16    [get_ports {eth1_wake}];        # FMC_LA07P = ETH1_WAKE
set_property PACKAGE_PIN G16    [get_ports {eth1_en}];          # FMC_LA07N = ETH1_TAJ_EN
set_property PACKAGE_PIN B19    [get_ports {eth1_mdir}];        # FMC_LA11P = ETH1_MD_DIR
set_property PACKAGE_PIN A22    [get_ports {eth2_rstn}];        # FMC_LA15N = ETH2_RST_N
set_property PACKAGE_PIN G22    [get_ports {eth3_rstn}];        # FMC_LA25P = ETH3_RST_N

# Status indicators and other control.
set_property PACKAGE_PIN M26    [get_ports {stat_led_g}];       # GPIO_LED_0
set_property PACKAGE_PIN T24    [get_ports {stat_led_r}];       # GPIO_LED_1
set_property PACKAGE_PIN U19    [get_ports {host_tx}];          # USB_UART_RX
set_property PACKAGE_PIN T19    [get_ports {host_rx}];          # USB_UART_TX
set_property PACKAGE_PIN U4     [get_ports {ext_reset_p}];      # CPU_RESET
set_property PACKAGE_PIN L25    [get_ports {lcd_db[0]}];        # LCD_DB4_LS
set_property PACKAGE_PIN M24    [get_ports {lcd_db[1]}];        # LCD_DB5_LS
set_property PACKAGE_PIN M25    [get_ports {lcd_db[2]}];        # LCD_DB6_LS
set_property PACKAGE_PIN L22    [get_ports {lcd_db[3]}];        # LCD_DB7_LS
set_property PACKAGE_PIN L20    [get_ports {lcd_e}];            # LCD_E_LS
set_property PACKAGE_PIN L24    [get_ports {lcd_rw}];           # LCD_RW_LS
set_property PACKAGE_PIN L23    [get_ports {lcd_rs}];           # LCD_RS_LS

#####################################################################
### Set all voltages and signaling standards

# The LCD and status LEDs are at 3.3V.
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_*}];
set_property IOSTANDARD LVCMOS33 [get_ports {stat_led_*}];

# All FMC interface pins are at 2.5V.
set_property IOSTANDARD LVCMOS25 [get_ports {rmii_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {eos_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {sja_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {mdio_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {eth1_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {eth2_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {eth3_*}];

# USB-UART interface is at 1.8V.
set_property IOSTANDARD LVCMOS18 [get_ports {host_*}];

# The "CPU reset" button is at 1.5V.
set_property IOSTANDARD LVCMOS15 [get_ports {ext_reset_p}];

# CFGBVS pin = 3.3V.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################
