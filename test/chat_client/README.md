# Chat-Client Demo Application.

![SatCat5 Logo](../../doc/images/satcat5.svg)

A simple "chatroom" demo that can exchange raw-Ethernet frames between various network nodes. It also provides the MDIO startup commands that are required to configure the AR8031 PHY that is included on the prototype reference PCB. Each chatroom node can be a regular Ethernet network interfaces or a UART.

Tested with: Windows 10, Anaconda 5.3.1, pyserial 3.4, scapy 2.4.0, numpy 1.17.2, PyQt5 5.13.1.
Additional requirements: [NPCAP](https://nmap.org/npcap/) installed for windows, [ft232 driver](http://www.ftdichip.com/Drivers/VCP.htm) installed

Note: Use "pyserial" library, not "serial".  If you install the other by mistake, uninstall both and start from scratch.

Note: Scapy v2.4.2 has a bug under Windows; version 2.4.0 is known to work.

![Screenshot of the chat application](../../doc/images/chat_screenshot.png)

# Copyright Notice

Copyright 2019 The Aerospace Corporation

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
along with SatCat5.  If not, see [https://www.gnu.org/licenses/](https://www.gnu.org/licenses/).
