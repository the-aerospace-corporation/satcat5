# Chat-Client Demo Application.

![SatCat5 Logo](../../doc/images/satcat5.svg)

A simple "chatroom" demo that can exchange raw-Ethernet frames between various network nodes. It also provides the MDIO startup commands that are required to configure the AR8031 PHY that is included on the prototype reference PCB. Each chatroom node can be a regular Ethernet network interfaces or a UART.

Tested with: Windows 10, Anaconda 5.3.1, pyserial 3.4, scapy 2.4.0, numpy 1.17.2, PyQt5 5.13.1.
Additional requirements: [NPCAP](https://nmap.org/npcap/) installed for windows, [ft232 driver](http://www.ftdichip.com/Drivers/VCP.htm) installed

Note: Use "pyserial" library, not "serial".  If you install the other by mistake, uninstall both and start from scratch.

Note: Scapy v2.4.2 has a bug under Windows; version 2.4.0 is known to work.

![Screenshot of the chat application](../../doc/images/chat_screenshot.png)

# Copyright Notice

Copyright 2020 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
