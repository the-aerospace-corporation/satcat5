# ------------------------------------------------------------------------
# Copyright 2020 The Aerospace Corporation
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
# ------------------------------------------------------------------------
#
# This script creates all of the port_xx and switch_xx IP-cores, which
# can be used in creating Vivado's drag-and-drop block diagram system.
# This script is not required when instantiating modules in regular HDL.
#

# Call script to generate each IP core.
source ipcores/create_port_adapter.tcl
source ipcores/create_port_axi_mailbox.tcl
source ipcores/create_port_crosslink.tcl
source ipcores/create_port_gmii_internal.tcl
source ipcores/create_port_inline_status.tcl
source ipcores/create_port_rmii.tcl
source ipcores/create_port_rgmii.tcl
source ipcores/create_port_serial_auto.tcl
source ipcores/create_port_serial_spi_clkin.tcl
source ipcores/create_port_serial_spi_clkout.tcl
source ipcores/create_port_serial_uart_2wire.tcl
source ipcores/create_port_serial_uart_4wire.tcl
source ipcores/create_port_sgmii_gpio.tcl
source ipcores/create_port_sgmii_gtx.tcl
source ipcores/create_router_inline.tcl
source ipcores/create_switch_aux.tcl
source ipcores/create_switch_core.tcl
source ipcores/create_switch_dual.tcl
source ipcores/create_switch_gmii_to_spi.tcl
