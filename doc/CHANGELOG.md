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

## 1.2.2

* Fixed AXI4-Lite compliance issues the "port_axi_mailbox" block.

## v1.3.0

* Add support for 802.3D pause-frames.
* Improved error-handling and error-recovery on SGMII ports.
* Improved performance of Python/ScaPy interfaces by using L2Socket objects.
* Update eth_frame_check to block frames where the source MAC is the broadcast address.

## v1.3.1

* Hotfix for inoperable router_config_axi block.

## v1.4.0

* Added diagnostic status flags to the internal Ethernet port definition.
* Compatibility improvements for SGMII startup handshake.
* Timing improvements for traffic statistic counters.

## v2.0.0

* Added a large number of auxiliary ConfigBus peripherals, with cross-platform software drivers.
* Added I2C peripherals and Ethernet-over-I2C ports.
* Added the "MailMap" port, a higher-performance analogue to original MailBox port.
* Created an embedded cross-platform C++ driver framework, including a IP and UDP network stack.
* Replaced all prior MAC-lookup systems with a flexible high-performance TCAM.
* Replaced various ad-hoc control and configuration functions with "ConfigBus".
* Reworked switch-core to allow higher maximum throughput, max one full packet per clock.
* Reworked switch-core to allow rudimentary IGMP snooping.
* Reworked switch-core to allow traffic prioritization based on EtherType.

## v2.0.1

* Added read/write functions for s8, s16, s32, and s64.
* Hotfix for UART-16550 driver and Arty-Managed example design.

## v2.1.0

* Added Virtual-LAN support (IEEE 802.1Q) to the Ethernet switch and the software network stack.
* Defined API for 10-gigabit Ethernet ports.
* Bug-fixes for eth_preamble_rx and port_inline_status.

# Copyright Notice

Copyright 2019, 2020, 2021 The Aerospace Corporation

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
