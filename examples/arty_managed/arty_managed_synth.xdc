# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Synthesis constraints for arty_managed
# Define pin locations and I/O standards only.

#####################################################################
### Set all I/O pin locations

# Reference clock and reset
set_property PACKAGE_PIN C2     [get_ports ext_reset_n];
set_property PACKAGE_PIN E3     [get_ports ext_clk100];

# Eth0 = Uplink RMII interface.
# (Tx/Rx direct connection for MAC-to-PHY interface.)
set_property PACKAGE_PIN F16    [get_ports mdio_clk];
set_property PACKAGE_PIN K13    [get_ports mdio_data];
set_property PACKAGE_PIN G14    [get_ports rmii_crs_dv];
set_property PACKAGE_PIN C17    [get_ports rmii_rx_er];
set_property PACKAGE_PIN D18    [get_ports {rmii_rxd[0]}];
set_property PACKAGE_PIN E17    [get_ports {rmii_rxd[1]}];
set_property PACKAGE_PIN H15    [get_ports rmii_tx_en];
set_property PACKAGE_PIN H14    [get_ports {rmii_txd[0]}];
set_property PACKAGE_PIN J14    [get_ports {rmii_txd[1]}];
set_property PACKAGE_PIN G18    [get_ports rmii_clkout];    # 50 MHz clock reference
set_property PACKAGE_PIN G16    [get_ports rmii_mode];      # Bootstrap to RMII mode
set_property PACKAGE_PIN C16    [get_ports rmii_resetn];

# PMOD JA = EoS-PMOD1
# Pin 1/2/3/4 = RTSb, RXD, TXD, CTSb = Out, In, Out, In wrt USB-UART
# Pin 1/2/3/4 = CTSb, TXD, RXD, RTSb = In, Out, In, Out wrt FPGA
set_property PACKAGE_PIN G13    [get_ports {pmod1[0]}];
set_property PACKAGE_PIN B11    [get_ports {pmod1[1]}];
set_property PACKAGE_PIN A11    [get_ports {pmod1[2]}];
set_property PACKAGE_PIN D12    [get_ports {pmod1[3]}];

# PMOD JB = EoS-PMOD2
set_property PACKAGE_PIN E15    [get_ports {pmod2[0]}];
set_property PACKAGE_PIN E16    [get_ports {pmod2[1]}];
set_property PACKAGE_PIN D15    [get_ports {pmod2[2]}];
set_property PACKAGE_PIN C15    [get_ports {pmod2[3]}];

# PMOD JC = EoS-PMOD3
set_property PACKAGE_PIN U12    [get_ports {pmod3[0]}];
set_property PACKAGE_PIN V12    [get_ports {pmod3[1]}];
set_property PACKAGE_PIN V10    [get_ports {pmod3[2]}];
set_property PACKAGE_PIN V11    [get_ports {pmod3[3]}];

# PMOD JC = EoS-PMOD4
set_property PACKAGE_PIN D4     [get_ports {pmod4[0]}];
set_property PACKAGE_PIN D3     [get_ports {pmod4[1]}];
set_property PACKAGE_PIN F4     [get_ports {pmod4[2]}];
set_property PACKAGE_PIN F3     [get_ports {pmod4[3]}];

# I2C interface (J3)
set_property PACKAGE_PIN L18    [get_ports i2c_sck];        # CK_SCL
set_property PACKAGE_PIN M18    [get_ports i2c_sda];        # CK_SDA

# LED status indicators.
set_property PACKAGE_PIN E1     [get_ports {leds[0]}];      # LED0_B
set_property PACKAGE_PIN F6     [get_ports {leds[1]}];      # LED0_G
set_property PACKAGE_PIN G6     [get_ports {leds[2]}];      # LED0_R
set_property PACKAGE_PIN G4     [get_ports {leds[3]}];      # LED1_B
set_property PACKAGE_PIN J4     [get_ports {leds[4]}];      # LED1_G
set_property PACKAGE_PIN G3     [get_ports {leds[5]}];      # LED1_R
set_property PACKAGE_PIN H4     [get_ports {leds[6]}];      # LED2_B
set_property PACKAGE_PIN J2     [get_ports {leds[7]}];      # LED2_G
set_property PACKAGE_PIN J3     [get_ports {leds[8]}];      # LED2_R
set_property PACKAGE_PIN K2     [get_ports {leds[9]}];      # LED3_B
set_property PACKAGE_PIN H6     [get_ports {leds[10]}];     # LED3_G
set_property PACKAGE_PIN K1     [get_ports {leds[11]}];     # LED3_R
set_property PACKAGE_PIN H5     [get_ports {leds[12]}];     # LED4
set_property PACKAGE_PIN J5     [get_ports {leds[13]}];     # LED5
set_property PACKAGE_PIN T9     [get_ports {leds[14]}];     # LED6
set_property PACKAGE_PIN T10    [get_ports {leds[15]}];     # LED7

# SPI interface (J6)
set_property PACKAGE_PIN C1     [get_ports spi_csb];        # CK_SS
set_property PACKAGE_PIN F1     [get_ports spi_sck];        # CK_SCK
set_property PACKAGE_PIN G1     [get_ports spi_sdi];        # CK_MISO
set_property PACKAGE_PIN H1     [get_ports spi_sdo];        # CK_MOSI

# USB-UART Interface
set_property PACKAGE_PIN D10    [get_ports uart_txd];
set_property PACKAGE_PIN A9     [get_ports uart_rxd];

# Debug LCD on ChipKit header
set_property PACKAGE_PIN V15    [get_ports {text_lcd_db[0]}];
set_property PACKAGE_PIN U16    [get_ports {text_lcd_db[1]}];
set_property PACKAGE_PIN P14    [get_ports {text_lcd_db[2]}];
set_property PACKAGE_PIN T11    [get_ports {text_lcd_db[3]}];
set_property PACKAGE_PIN R12    [get_ports text_lcd_e];
set_property PACKAGE_PIN T14    [get_ports text_lcd_rw];
set_property PACKAGE_PIN T15    [get_ports text_lcd_rs];

#####################################################################
### Set all voltages and signaling standards

# All I/O pins at 3.3V
set_property IOSTANDARD LVCMOS33 [get_ports ext_clk100];
set_property IOSTANDARD LVCMOS33 [get_ports ext_reset_n];
set_property IOSTANDARD LVCMOS33 [get_ports i2c*];
set_property IOSTANDARD LVCMOS33 [get_ports leds*];
set_property IOSTANDARD LVCMOS33 [get_ports mdio*];
set_property IOSTANDARD LVCMOS33 [get_ports pmod*];
set_property IOSTANDARD LVCMOS33 [get_ports rmii*];
set_property IOSTANDARD LVCMOS33 [get_ports spi*];
set_property IOSTANDARD LVCMOS33 [get_ports uart*];
set_property IOSTANDARD LVCMOS33 [get_ports text_lcd*];

# CFGBVS pin = 3.3V.
set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################


