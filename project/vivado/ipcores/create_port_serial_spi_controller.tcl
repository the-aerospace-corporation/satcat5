# ------------------------------------------------------------------------
# Copyright 2020, 2021, 2022 The Aerospace Corporation
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
# This script packages a Vivado IP core: satcat5.port_serial_spi_controller
#

# Create a basic IP-core project.
set ip_name "port_serial_spi_controller"
set ip_vers "1.0"
set ip_disp "SatCat5 SPI PHY (Controller)"
set ip_desc "Mixed-media Ethernet-over-SPI port with clock and CSb as outputs."

set ip_root [file normalize [file dirname [info script]]]
source $ip_root/ipcore_shared.tcl

# Add all required source files:
ipcore_add_file $src_dir/common/*.vhd
ipcore_add_top  $ip_root/wrap_port_serial_spi_controller.vhd

# Connect I/O ports
ipcore_add_gpio ext_pads
ipcore_add_ethport Eth sw master
ipcore_add_clock refclk Eth
ipcore_add_reset reset_p ACTIVE_HIGH
ipcore_add_cfgopt Cfg cfg

# Set parameters
ipcore_add_param CLKREF_HZ long 100000000 \
    {Frequency of "refclk" signal (Hz)}
ipcore_add_param SPI_BAUD long 10000000 \
    {SPI baud rate (Hz)}
ipcore_add_param SPI_MODE long 3 \
    {SPI clock phase and polarity (Mode = 0-3)}

# Package the IP-core.
ipcore_finished
