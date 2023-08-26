# Arty-Managed OLED demo

Arty-Managed is an example design for SatCat5.
The design turns a Digilent Arty-35T or -100T into a mixed-media Ethernet
switch, which has various management functions.  It includes a remotely
controlled I2C port that is enabled by default.

This folder contains a configuration tool that has been implemented in both
C++ and Python.  Both versions have identical functionality, using the I2C
port to control an SSD1306 OLED screen.  At regular intervals, it prints
various messages to the OLED screen.

Connect the OLED screen to the Arty as follows:
    * Connect OLED SCL and SDA pins to J3.
    * Connect OLED power pin (+3.3V) and ground pin.
    * Connect a USB-UART to your PC and to any PMOD port.
    * Connect Arty to USB power source and load Arty-managed bitfile.

# Usage (C++)

Run "make all", then run "oled_demo.bin [uart_name]",
where uart_name is the name of a USB-UART attached to the Arty board.
(e.g., Something similar to "COM4" on Windows or "/dev/ttyusb0" on Linux.)

# Usage (Python)

Run "python3 oled_demo.py [uart_name]" (see notes above).

# Copyright Notice

Copyright 2023 The Aerospace Corporation

This file is part of SatCat5.

SatCat5 is free software: you can redistribute it and/or modify it under
the terms of the GNU Lesser General Public License as published by the
Free Software Foundation, either version 3 of the License, or (at your
option) any later version.

SatCat5 is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public License
along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
