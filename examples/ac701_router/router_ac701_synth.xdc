# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

#####################################################################
### Set all I/O pin locations

# RGMII PHY #9 on the AC701 board (88E1116R)
set_property PACKAGE_PIN U21    [get_ports {rgmii0_rxc}];       # PHY_RX_CLK
set_property PACKAGE_PIN U17    [get_ports {rgmii0_rd[0]}];     # PHY_RXD0
set_property PACKAGE_PIN V17    [get_ports {rgmii0_rd[1]}];     # PHY_RXD1
set_property PACKAGE_PIN V16    [get_ports {rgmii0_rd[2]}];     # PHY_RXD2
set_property PACKAGE_PIN V14    [get_ports {rgmii0_rd[3]}];     # PHY_RXD3
set_property PACKAGE_PIN U14    [get_ports {rgmii0_rx_ctl}];    # PHY_RX_CTRL
set_property PACKAGE_PIN U22    [get_ports {rgmii0_txc}];       # PHY_TX_CLK
set_property PACKAGE_PIN U16    [get_ports {rgmii0_td[0]}];     # PHY_TXD0
set_property PACKAGE_PIN U15    [get_ports {rgmii0_td[1]}];     # PHY_TXD1
set_property PACKAGE_PIN T18    [get_ports {rgmii0_td[2]}];     # PHY_TXD2
set_property PACKAGE_PIN T17    [get_ports {rgmii0_td[3]}];     # PHY_TXD3
set_property PACKAGE_PIN T15    [get_ports {rgmii0_tx_ctl}];    # PHY_TX_CTRL
set_property PACKAGE_PIN V18    [get_ports {rgmii0_rst_b}];     # PHY_RESET_B

# RGMII PHY #1 on the Avnet FMC board (KSZ9031RNXIC)
set_property PACKAGE_PIN D18    [get_ports {rgmii1_rxc}];       # FMC_LA00P = ETH1_RX_CLK
set_property PACKAGE_PIN H14    [get_ports {rgmii1_rd[0]}];     # FMC_LA02P = ETH1_RX_D0
set_property PACKAGE_PIN H15    [get_ports {rgmii1_rd[1]}];     # FMC_LA02N = ETH1_RX_D1
set_property PACKAGE_PIN G17    [get_ports {rgmii1_rd[2]}];     # FMC_LA03P = ETH1_RX_D2
set_property PACKAGE_PIN F17    [get_ports {rgmii1_rd[3]}];     # FMC_LA03N = ETH1_RX_D3
set_property PACKAGE_PIN C18    [get_ports {rgmii1_rx_ctl}];    # FMC_LA00N = ETH1_RX_DV
set_property PACKAGE_PIN F19    [get_ports {rgmii1_txc}];       # FMC_LA04N = ETH1_TX_CLK
set_property PACKAGE_PIN F18    [get_ports {rgmii1_td[0]}];     # FMC_LA04P = ETH1_TX_D0
set_property PACKAGE_PIN C17    [get_ports {rgmii1_td[1]}];     # FMC_LA08P = ETH1_TX_D1
set_property PACKAGE_PIN B17    [get_ports {rgmii1_td[2]}];     # FMC_LA08N = ETH1_TX_D2
set_property PACKAGE_PIN H16    [get_ports {rgmii1_td[3]}];     # FMC_LA07P = ETH1_TX_D3
set_property PACKAGE_PIN G16    [get_ports {rgmii1_tx_ctl}];    # FMC_LA07N = ETH1_TX_EN
set_property PACKAGE_PIN F15    [get_ports {rgmii1_rst_b}];     # FMC_LA05N = ETH1_RST_N

# RGMII PHY #2 on the Avnet FMC board (KSZ9031RNXIC)
set_property PACKAGE_PIN E17    [get_ports {rgmii2_rxc}];       # FMC_LA01P = ETH2_RX_CLK
set_property PACKAGE_PIN G19    [get_ports {rgmii2_rd[0]}];     # FMC_LA06P = ETH2_RX_D0
set_property PACKAGE_PIN E16    [get_ports {rgmii2_rd[1]}];     # FMC_LA09P = ETH2_RX_D1
set_property PACKAGE_PIN A18    [get_ports {rgmii2_rd[2]}];     # FMC_LA10N = ETH2_RX_D2
set_property PACKAGE_PIN D16    [get_ports {rgmii2_rd[3]}];     # FMC_LA09N = ETH2_RX_D3
set_property PACKAGE_PIN E18    [get_ports {rgmii2_rx_ctl}];    # FMC_LA01N = ETH2_RX_DV
set_property PACKAGE_PIN A19    [get_ports {rgmii2_txc}];       # FMC_LA11N = ETH2_TX_CLK
set_property PACKAGE_PIN D20    [get_ports {rgmii2_td[0]}];     # FMC_LA12N = ETH2_TX_D0
set_property PACKAGE_PIN B19    [get_ports {rgmii2_td[1]}];     # FMC_LA11P = ETH2_TX_D1
set_property PACKAGE_PIN E21    [get_ports {rgmii2_td[2]}];     # FMC_LA16P = ETH2_TX_D2
set_property PACKAGE_PIN D21    [get_ports {rgmii2_td[3]}];     # FMC_LA16N = ETH2_TX_D3
set_property PACKAGE_PIN B22    [get_ports {rgmii2_tx_ctl}];    # FMC_LA15P = ETH2_TX_EN
set_property PACKAGE_PIN A22    [get_ports {rgmii2_rst_b}];     # FMC_LA15N = ETH2_RST_N

# Other AC701 peripherals:
set_property PACKAGE_PIN R3     [get_ports {refclk200_clk_p}];  # SYSCLK_P
set_property PACKAGE_PIN P3     [get_ports {refclk200_clk_n}];  # SYSCLK_N
set_property PACKAGE_PIN U4     [get_ports {reset_p}];          # CPU_RESET
set_property PACKAGE_PIN P16    [get_ports {scrub_clk}];        # FPGA_EMCCLK
set_property PACKAGE_PIN U19    [get_ports {status_uart}];      # USB_UART_RX
set_property PACKAGE_PIN L25    [get_ports {text_lcd_db[0]}];   # LCD_DB4_LS
set_property PACKAGE_PIN M24    [get_ports {text_lcd_db[1]}];   # LCD_DB5_LS
set_property PACKAGE_PIN M25    [get_ports {text_lcd_db[2]}];   # LCD_DB6_LS
set_property PACKAGE_PIN L22    [get_ports {text_lcd_db[3]}];   # LCD_DB7_LS
set_property PACKAGE_PIN L20    [get_ports {text_lcd_e}];       # LCD_E_LS
set_property PACKAGE_PIN L24    [get_ports {text_lcd_rw}];      # LCD_RW_LS
set_property PACKAGE_PIN L23    [get_ports {text_lcd_rs}];      # LCD_RS_LS

#####################################################################
### Set all voltages and signaling standards

# Set SLEW=FAST mode for all RGMII outputs.
set_property SLEW FAST [get_ports {rgmii0_tx*}]
set_property SLEW FAST [get_ports {rgmii1_tx*}]
set_property SLEW FAST [get_ports {rgmii2_tx*}]

# The EMC-clock, status LEDs, and text-LCD are at 3.3V.
set_property IOSTANDARD LVCMOS33 [get_ports {scrub_clk}];
set_property IOSTANDARD LVCMOS33 [get_ports {text_lcd_*}];

# System clock is LVDS, externally terminated.
set_property IOSTANDARD LVDS_25 [get_ports {refclk200_*}];
set_property DIFF_TERM FALSE [get_ports {refclk200_*}];

# All FMC interface pins are at 2.5V.
set_property IOSTANDARD LVCMOS25 [get_ports {rgmii1_*}];
set_property IOSTANDARD LVCMOS25 [get_ports {rgmii2_*}];

# RGMII0 and USB-UART interfaces are at 1.8V.
set_property IOSTANDARD LVCMOS18 [get_ports {rgmii0_*}];
set_property IOSTANDARD LVCMOS18 [get_ports {status_uart}];

# The "CPU reset" button is at 1.5V.
set_property IOSTANDARD LVCMOS15 [get_ports {reset_p}];

# CFGBVS pin = 3.3V.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
