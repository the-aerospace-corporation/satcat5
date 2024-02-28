# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Synthesis constraints for switch_top_ext_ac701
# Define pin locations and I/O standards only.

#####################################################################
### Set all I/O pin locations

# Eth0 = Uplink RGMII interface.
# (Tx/Rx crossover connection for MAC-to-MAC interface.)
set_property PACKAGE_PIN E17    [get_ports {uplnk_rxc}];        # FMC_LA01P = ETH0_TX_CLK
set_property PACKAGE_PIN G15    [get_ports {uplnk_rxd[0]}];     # FMC_LA05P = ETH0_TX_D0
set_property PACKAGE_PIN F15    [get_ports {uplnk_rxd[1]}];     # FMC_LA05N = ETH0_TX_D1
set_property PACKAGE_PIN E16    [get_ports {uplnk_rxd[2]}];     # FMC_LA09P = ETH0_TX_D2
set_property PACKAGE_PIN D16    [get_ports {uplnk_rxd[3]}];     # FMC_LA09N = ETH0_TX_D3
set_property PACKAGE_PIN B20    [get_ports {uplnk_rxctl}];      # FMC_LA13P = ETH0_TX_EN
set_property PACKAGE_PIN K21    [get_ports {uplnk_txc}];        # FMC_LA17P = ETH0_RX_CLK
set_property PACKAGE_PIN K20    [get_ports {uplnk_txd[0]}];     # FMC_LA23P = ETH0_RX_D0
set_property PACKAGE_PIN J20    [get_ports {uplnk_txd[1]}];     # FMC_LA23N = ETH0_RX_D1
set_property PACKAGE_PIN J24    [get_ports {uplnk_txd[2]}];     # FMC_LA26P = ETH0_RX_D2
set_property PACKAGE_PIN H24    [get_ports {uplnk_txd[3]}];     # FMC_LA26N = ETH0_RX_D3
set_property PACKAGE_PIN E23    [get_ports {uplnk_txctl}];      # FMC_LA27N = ETH0_RX_DV

# Eth3 = Direct RGMII interface.
# (Tx/Rx direct connection for MAC-to-PHY interface.)
set_property PACKAGE_PIN D18    [get_ports {rgmii_txc}];        # FMC_LA00P = ETH3_TX_CLK
set_property PACKAGE_PIN G17    [get_ports {rgmii_txd[0]}];     # FMC_LA03P = ETH3_TX_D0
set_property PACKAGE_PIN F17    [get_ports {rgmii_txd[1]}];     # FMC_LA03N = ETH3_TX_D1
set_property PACKAGE_PIN C17    [get_ports {rgmii_txd[2]}];     # FMC_LA08P = ETH3_TX_D2
set_property PACKAGE_PIN B17    [get_ports {rgmii_txd[3]}];     # FMC_LA08N = ETH3_TX_D3
set_property PACKAGE_PIN E20    [get_ports {rgmii_txctl}];      # FMC_LA12P = ETH3_TX_EN
set_property PACKAGE_PIN C18    [get_ports {rgmii_rxc}];        # FMC_LA00N = ETH3_RX_CLK
set_property PACKAGE_PIN D20    [get_ports {rgmii_rxd[0]}];     # FMC_LA12N = ETH3_RX_D0
set_property PACKAGE_PIN E21    [get_ports {rgmii_rxd[1]}];     # FMC_LA16P = ETH3_RX_D1
set_property PACKAGE_PIN D21    [get_ports {rgmii_rxd[2]}];     # FMC_LA26N = ETH3_RX_D2
set_property PACKAGE_PIN M16    [get_ports {rgmii_rxd[3]}];     # FMC_LA20P = ETH3_RX_D3
set_property PACKAGE_PIN M17    [get_ports {rgmii_rxctl}];      # FMC_LA20N = ETH3_RX_DV

# Eth2, Eth3 = SGMII interfaces.
# Note: Specify positive pin in each pair; Vivado can figure out the rest.
set_property PACKAGE_PIN J19    [get_ports {sgmii_rxp[0]}];     # FMC_LA21P = ETH2_SOP
set_property PACKAGE_PIN J18    [get_ports {sgmii_rxp[1]}];     # FMC_LA24P = ETH3_SOP
set_property PACKAGE_PIN K22    [get_ports {sgmii_txp[0]}];     # FMC_LA28P = ETH2_SIP
set_property PACKAGE_PIN E25    [get_ports {sgmii_txp[1]}];     # FMC_LA30P = ETH3_SIP

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
set_property PACKAGE_PIN T8     [get_ports {clkout25_p}];       # USER_SMA_GPIO_P
set_property PACKAGE_PIN T7     [get_ports {clkout25_n}];       # USER_SMA_GPIO_N
set_property PACKAGE_PIN M26    [get_ports {stat_led_g}];       # GPIO_LED_0
set_property PACKAGE_PIN T24    [get_ports {stat_led_y}];       # GPIO_LED_1
set_property PACKAGE_PIN T25    [get_ports {stat_led_r}];       # GPIO_LED_2
set_property PACKAGE_PIN U19    [get_ports {host_tx}];          # USB_UART_RX
set_property PACKAGE_PIN T19    [get_ports {host_rx}];          # USB_UART_TX
set_property PACKAGE_PIN J23    [get_ports {ext_clk25}];        # USER_SMA_CLOCK_P
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
# Note: IOSTANDARD for SGMII pins is set in HDL.
set_property IOSTANDARD LVCMOS25 [get_ports {uplnk_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {rgmii_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {eos_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {sja_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {mdio_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {eth1_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {eth2_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {eth3_*}];

# External clock reference is at 2.5V
set_property IOSTANDARD LVCMOS25 [get_ports {ext_clk25}];

# USB-UART interface is at 1.8V.
set_property IOSTANDARD LVCMOS18 [get_ports {host_*}];

# The "CPU reset" button and "CLKOUT_25" signals are at 1.5V.
set_property IOSTANDARD LVCMOS15 [get_ports {ext_reset_p}];
set_property IOSTANDARD LVCMOS15 [get_ports {clkout25_*}];

# CFGBVS pin = 3.3V.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

#####################################################################
### Other build settings

# Disable spurious error regarding clock-switchover compensation.
# (Frequency reference only; we simply don't care about source phase.)
# The REQP-119 check occurs before implementation constraints are read,
# so it's easiest to simply disable it during synthesis.
set_property is_enabled false [get_drc_checks REQP-119]

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################
