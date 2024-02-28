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

Copyright 2023 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
