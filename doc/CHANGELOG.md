# SatCat5 Change Log

![SatCat5 Logo](images/satcat5.svg)

This log will be updated for each new release, but may not reflect the latest development branch(es).

## v1.0.0

* Initial release of the SatCat5 mixed-media Ethernet switch.
* Supported FPGA platforms: Lattice iCE40, Xilinx 7-Series
* Supported Ethernet interfaces: RMII, RGMII, SGMII, SPI, UART
* Also included: Example designs for the Arty A7 as well as several [custom boards](../test/proto_pcb/README.md), the [PiWire](../test/pi_wire/readme.md) adapter software, a Python-based mixed-media-Ethernet [chatroom demo](../test/chat_client/README.md), and Jenkins scripts for continuous integration and testing.

## v1.1.0

* Added platform support for the Microsemi Polarfire.
* New features including improved MAC-address lookup, a virtual port (AXI-mailbox), SPI ports with an output clock, and improved build scripting.

## v1.2.0

* Added contribution guidelines, issue templates, and pull-request templates to encourage outside contributions.
* Added IPv4 router block.
* New switch management features including traffic counters and per-port promiscuous-mode.
* Xilinx platform: Added block-diagram IP-core wrappers for many functional blocks.

# Copyright Notice

Copyright 2019, 2020 The Aerospace Corporation

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
