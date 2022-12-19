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

Copyright 2022 The Aerospace Corporation

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
