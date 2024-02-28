# Log-Viewer README

Several SatCat5 examples use a common format for text-based Chat/Log messages.

This folder contains a simple console application using PCAP/NPCAP to view these messages.

# Building

To build this application in a Linux environment, install "libpcap-dev".
(i.e., Run ""apt-get install libpcap-dev" or equivalent for your distribution.)

To build this application in a Windows environment, install:
* [MinGW](https://nuwen.net/mingw.html#install).
* [NPCAP](https://nmap.org/npcap/#download)
* NPCAP-SDK (link above) should be copied to "./npcap"

Once all prerequisites are installed, run "make run".

Note: On many distributions, using PCAP requires admin/root privileges.

# Copyright Notice

Copyright 2022-2023 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
