# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Synthesis constraints for "loopback_ac701"
# Define pin locations and I/O standards only.

#####################################################################
### Set all I/O pin locations

# SGMII loopback port:
#   Rx on "USR_SMA_GPIO_*" (VCCO = 1.5V + DIFF_SSTL15)
#   Tx on "USR_SMA_CLOCK_*" (VCCO = 2.5V + LVDS_25)
# Note: Specify positive pin in each pair; Vivado can figure out the rest.
set_property PACKAGE_PIN T8     [get_ports {sgmii_rxp}];        # Rx on "USR_SMA_GPIO_*"
set_property PACKAGE_PIN J23    [get_ports {sgmii_txp}];        # Tx on "USR_SMA_CLOCK_*"

# Reference clock
set_property PACKAGE_PIN R3     [get_ports {ext_clk200p}];      # SYSCLK_P
set_property PACKAGE_PIN P3     [get_ports {ext_clk200n}];      # SYSCLK_N

# Status indicators and other control.
set_property PACKAGE_PIN M26    [get_ports {stat_led_g}];       # GPIO_LED_0
set_property PACKAGE_PIN T24    [get_ports {stat_led_y}];       # GPIO_LED_1
set_property PACKAGE_PIN T25    [get_ports {stat_led_r}];       # GPIO_LED_2
set_property PACKAGE_PIN U19    [get_ports {uart_txd}];         # USB_UART_RX
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

# USB-UART interface is at 1.8V.
set_property IOSTANDARD LVCMOS18 [get_ports {uart_*}];

# The "CPU reset" button is at 1.5V.
set_property IOSTANDARD LVCMOS15 [get_ports {ext_reset_p}];

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
