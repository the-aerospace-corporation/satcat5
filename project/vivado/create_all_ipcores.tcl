# ------------------------------------------------------------------------
# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates all of the port_xx and switch_xx IP-cores, which
# can be used in creating Vivado's drag-and-drop block diagram system.
# This script is not required when instantiating modules in regular HDL.
#

puts {Running create_all_ipcores.tcl}

# Call script to generate each IP core.
# Note: This list skips cores with platform compatibility limitations.
#   If your project needs such a core, call the "create" script directly.
variable iproot [file normalize [file dirname [info script]]]
variable ipcores $iproot/ipcores
source $ipcores/create_cfgbus_gpi.tcl
source $ipcores/create_cfgbus_gpio.tcl
source $ipcores/create_cfgbus_gpo.tcl
source $ipcores/create_cfgbus_host_axi.tcl
source $ipcores/create_cfgbus_host_eth.tcl
source $ipcores/create_cfgbus_host_uart.tcl
source $ipcores/create_cfgbus_i2c_controller.tcl
source $ipcores/create_cfgbus_led.tcl
source $ipcores/create_cfgbus_mdio.tcl
source $ipcores/create_cfgbus_spi_controller.tcl
source $ipcores/create_cfgbus_split.tcl
source $ipcores/create_cfgbus_text_lcd.tcl
source $ipcores/create_cfgbus_timer.tcl
source $ipcores/create_cfgbus_uart.tcl
source $ipcores/create_port_adapter.tcl
source $ipcores/create_port_axi_mailbox.tcl
source $ipcores/create_port_axi_mailmap.tcl
source $ipcores/create_port_crosslink.tcl
source $ipcores/create_port_gmii_internal.tcl
source $ipcores/create_port_inline_status.tcl
source $ipcores/create_port_mailbox.tcl
source $ipcores/create_port_mailmap.tcl
source $ipcores/create_port_nullsink.tcl
source $ipcores/create_port_rgmii.tcl
source $ipcores/create_port_rmii.tcl
source $ipcores/create_port_serial_auto.tcl
source $ipcores/create_port_serial_i2c_controller.tcl
source $ipcores/create_port_serial_i2c_peripheral.tcl
source $ipcores/create_port_serial_spi_controller.tcl
source $ipcores/create_port_serial_spi_peripheral.tcl
source $ipcores/create_port_serial_uart_2wire.tcl
source $ipcores/create_port_serial_uart_4wire.tcl
source $ipcores/create_port_sgmii_gpio.tcl
source $ipcores/create_port_sgmii_gtx.tcl
#source $ipcores/create_port_sgmii_lvds.tcl
source $ipcores/create_port_sgmii_raw.tcl
source $ipcores/create_port_stream.tcl
source $ipcores/create_ptp_freqsynth.tcl
source $ipcores/create_ptp_reference.tcl
source $ipcores/create_reset_hold.tcl
source $ipcores/create_router_inline.tcl
source $ipcores/create_switch_aux.tcl
source $ipcores/create_switch_core.tcl
source $ipcores/create_switch_dual.tcl
source $ipcores/create_switch_gmii_to_spi.tcl
source $ipcores/create_ublaze_reset.tcl
