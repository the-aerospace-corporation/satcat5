# Pkt-Viewer README

SatCat5 switches and routers have the option to create a diagnostic log
that records basic information about each packet.  This information can
be directed to a UART interface.

This folder contains a simple console application to view these messages.

# Building

To build this application in a Linux environment, the only prerequisities
are GCC and Make.

To build this application in a Windows environment, install:
[MinGW](https://nuwen.net/mingw.html#install).

Once all prerequisites are installed, run "make run".

# Copyright Notice

Copyright 2025 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
