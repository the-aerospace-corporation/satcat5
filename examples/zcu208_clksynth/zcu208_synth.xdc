# Copyright 2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

#####################################################################
### Set all I/O pin locations

set_property PACKAGE_PIN AU1    [get_ports {ext_rst_p}];        # CPU_RESET
set_property PACKAGE_PIN AU4    [get_ports {clk_100_p}];        # CLK_100_P
set_property PACKAGE_PIN T31    [get_ports {clk_125_p}];        # USER_SMA_MGT_CLOCK_C_P
set_property PACKAGE_PIN G10    [get_ports {i2c1_scl}];         # PL_I2C1_SCL_LS
set_property PACKAGE_PIN K12    [get_ports {i2c1_sda}];         # PL_I2C1_SDA_LS
set_property PACKAGE_PIN C11    [get_ports {spi_mux[0]}];       # CLK104_CLK_SPI_MUX_SEL0
set_property PACKAGE_PIN B12    [get_ports {spi_mux[1]}];       # CLK104_CLK_SPI_MUX_SEL1
set_property PACKAGE_PIN AR19   [get_ports {status_led[0]}];    # GPIO_LED0_LS
set_property PACKAGE_PIN AT17   [get_ports {status_led[1]}];    # GPIO_LED1_LS
set_property PACKAGE_PIN AR17   [get_ports {status_led[2]}];    # GPIO_LED2_LS
set_property PACKAGE_PIN AU19   [get_ports {status_led[3]}];    # GPIO_LED3_LS
set_property PACKAGE_PIN AU20   [get_ports {status_led[4]}];    # GPIO_LED4_LS
set_property PACKAGE_PIN AW21   [get_ports {status_led[5]}];    # GPIO_LED5_LS
set_property PACKAGE_PIN AV21   [get_ports {status_led[6]}];    # GPIO_LED6_LS
set_property PACKAGE_PIN AV17   [get_ports {status_led[7]}];    # GPIO_LED7_LS
set_property PACKAGE_PIN AR8    [get_ports {uart_rx}];          # UART2_TXD_FPGA_RXD
set_property PACKAGE_PIN AT9    [get_ports {uart_tx}];          # UART2_RXD_FPGA_TXD
set_property PACKAGE_PIN AG14   [get_ports {uart_ctsb}];        # UART2_CTS_B

#####################################################################
### Set all voltages and signaling standards

set_property IOSTANDARD LVCMOS18 [get_ports {ext_rst_p}];
set_property IOSTANDARD LVCMOS12 [get_ports {i2c1_*}];
set_property IOSTANDARD LVCMOS12 [get_ports {spi_mux*}];
set_property IOSTANDARD LVCMOS12 [get_ports {status_led*}];
set_property IOSTANDARD LVCMOS12 [get_ports {uart_*}];
set_property IOSTANDARD LVDS_25 [get_ports {clk_100_*}];
set_property DRIVE 8 [get_ports {i2c*}];
set_property CONFIG_VOLTAGE 1.8 [current_design];

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################
