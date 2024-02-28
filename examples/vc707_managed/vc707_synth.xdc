# Copyright 2021-2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Synthesis constraints for vc707_managed
# Define pin locations and I/O standards only.

#####################################################################
### Set all I/O pin locations

set_property PACKAGE_PIN AV40   [get_ports {cpu_reset}];
set_property PACKAGE_PIN AP37   [get_ports {emc_clk}];
set_property PACKAGE_PIN AT32   [get_ports {usb_uart[0]}];  # USB_UART_RTS (FPGA-CTS)
set_property PACKAGE_PIN AU36   [get_ports {usb_uart[1]}];  # USB_UART_RX (FPGA-Tx)
set_property PACKAGE_PIN AU33   [get_ports {usb_uart[2]}];  # USB_UART_TX (FPGA-Rx)
set_property PACKAGE_PIN AR34   [get_ports {usb_uart[3]}];  # USB_UART_CTS (FPGA-RTS)
set_property PACKAGE_PIN AH8    [get_ports {mgt_clk_clk_p}];
set_property PACKAGE_PIN AH31   [get_ports {phy_mdio_sck}];
set_property PACKAGE_PIN AK33   [get_ports {phy_mdio_sda}];
set_property PACKAGE_PIN AT35   [get_ports {sfp_i2c_sck}];
set_property PACKAGE_PIN AU32   [get_ports {sfp_i2c_sda}];
set_property PACKAGE_PIN AM8    [get_ports {sgmii_rj45_rxp}];
set_property PACKAGE_PIN AN2    [get_ports {sgmii_rj45_txp}];
set_property PACKAGE_PIN AL6    [get_ports {basex_sfp_rxp}];
set_property PACKAGE_PIN AM4    [get_ports {basex_sfp_txp}];
set_property PACKAGE_PIN AM39   [get_ports {status_led[0]}];
set_property PACKAGE_PIN AN39   [get_ports {status_led[1]}];
set_property PACKAGE_PIN AR37   [get_ports {status_led[2]}];
set_property PACKAGE_PIN AT37   [get_ports {status_led[3]}];
set_property PACKAGE_PIN AR35   [get_ports {status_led[4]}];
set_property PACKAGE_PIN AP41   [get_ports {status_led[5]}];
set_property PACKAGE_PIN AP42   [get_ports {status_led[6]}];
set_property PACKAGE_PIN AU39   [get_ports {status_led[7]}];
set_property PACKAGE_PIN E19    [get_ports {sys_clk_clk_p}];
set_property PACKAGE_PIN AT42   [get_ports {text_lcd_lcd_db[0]}];
set_property PACKAGE_PIN AR38   [get_ports {text_lcd_lcd_db[1]}];
set_property PACKAGE_PIN AR39   [get_ports {text_lcd_lcd_db[2]}];
set_property PACKAGE_PIN AN40   [get_ports {text_lcd_lcd_db[3]}];
set_property PACKAGE_PIN AT40   [get_ports {text_lcd_lcd_e}];
set_property PACKAGE_PIN AN41   [get_ports {text_lcd_lcd_rs}];
set_property PACKAGE_PIN AR42   [get_ports {text_lcd_lcd_rw}];

#####################################################################
### Set all voltages and signaling standards

# All single-ended I/O pins at 1.8V
set_property IOSTANDARD LVCMOS18 [get_ports cpu_reset];
set_property IOSTANDARD LVCMOS18 [get_ports emc_clk];
set_property IOSTANDARD LVCMOS18 [get_ports usb_uart*];
set_property IOSTANDARD LVCMOS18 [get_ports phy_mdio*];
set_property IOSTANDARD LVCMOS18 [get_ports sfp_i2c*];
set_property IOSTANDARD LVCMOS18 [get_ports status_led*];
set_property IOSTANDARD LVCMOS18 [get_ports text_lcd*];

# CFGBVS pin = GND.
set_property CFGBVS GND [current_design];
set_property CONFIG_VOLTAGE 1.8 [current_design];

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################
