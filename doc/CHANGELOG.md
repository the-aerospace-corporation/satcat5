# SatCat5 Change Log

![SatCat5 Logo](images/satcat5.svg)

This log will be updated for each new release, but may not reflect the latest development branch(es).

## v2.5.0 (2024 February)

* License changed to CERN-OHL-W v2 or later.
* Added a software-based PTP client and clock-tuning interfaces.
* Added a software-based TFTP client and server.
* Added diagnostic tools for working with PCAP and PCAPNG files.
* Added support for many additional CRC16 and CRC32 formats.
* Improved log-message filtering for many unit tests.
* Improved status telemetry for managed switch diagnostics.
* New example design "vc707_ptp_client".

## v2.4.0 (2023 August)

* Added per-VLAN rate-limiting and associated device drivers.
* Added Slingshot interface control documents (ICDs).
* Added software-based DHCP client and server.
* Fixed "bidir_io" support on Lattice FPGAs.
* Fixed "mac_lookup" threshold for instantiating a second TCAM unit.
* Performance and tracking-filter improvements for PTP.
* Software support for 10-bit I2C addresses.
* Software support for various CBOR-encoded messages.

## v2.3.0 (2023 February)

* New `zcu208_clksynth` example design and associated device drivers.
* New `sgmii_lvds` IP-core.
* Port mode (port_serial_auto) is now CPU-configurable.
* Refactor C++ test utilities for better code-reuse.
* Update cfg::NetworkStats driver to allow remote access.
* Update poll::OnDemand main loop to prevent orphaned tasks.
* Update documenation and TCL scripts.

## v2.2.0 (2022 December)

* Added Vernier-PLL system for timestamps with sub-nanosecond precision.
* Defined API for ingress and egress timestamps and integrated with all SatCat5 port types.
* More formatting options for the `satcat5::log` API, including signed decimal numbers.
* New all-in-one IP/UDP network stack for simplified software networking.
* New `log_viewer` diagnostic tool for display of messages from the `satcat5::log` API.
* Reworked TCAM and MAC-lookup blocks to allow runtime read/write of MAC-address tables.
* Tooltips for all IP-core configuration parameters.
* Bug-fixes for router_inline and MDIO device-driver.

## v2.1.0 (2021 December)

* Added Virtual-LAN support (IEEE 802.1Q) to the Ethernet switch and the software network stack.
* Defined API for 10-gigabit Ethernet ports.
* Bug-fixes for eth_preamble_rx and port_inline_status.

## v2.0.1 (2021 October)

* Added read/write functions for s8, s16, s32, and s64.
* Hotfix for UART-16550 driver and Arty-Managed example design.

## v2.0.0 (2021 September)

* Added a large number of auxiliary ConfigBus peripherals, with cross-platform software drivers.
* Added I2C peripherals and Ethernet-over-I2C ports.
* Added the "MailMap" port, a higher-performance analogue to original MailBox port.
* Created an embedded cross-platform C++ driver framework, including a IP and UDP network stack.
* Replaced all prior MAC-lookup systems with a flexible high-performance TCAM.
* Replaced various ad-hoc control and configuration functions with "ConfigBus".
* Reworked switch-core to allow higher maximum throughput, max one full packet per clock.
* Reworked switch-core to allow rudimentary IGMP snooping.
* Reworked switch-core to allow traffic prioritization based on EtherType.

## v1.4.0 (2021 March)

* Added diagnostic status flags to the internal Ethernet port definition.
* Compatibility improvements for SGMII startup handshake.
* Timing improvements for traffic statistic counters.

## v1.3.1 (2021 February)

* Hotfix for inoperable router_config_axi block.

## v1.3.0 (2021 January)

* Add support for 802.3D pause-frames.
* Improved error-handling and error-recovery on SGMII ports.
* Improved performance of Python/ScaPy interfaces by using L2Socket objects.
* Update eth_frame_check to block frames where the source MAC is the broadcast address.

## v1.2.2 (2020 October)

* Fixed AXI4-Lite compliance issues the `port_axi_mailbox` block.

## v1.2.0 (2020 September)

* Added contribution guidelines, issue templates, and pull-request templates to encourage outside contributions.
* Added IPv4 router block.
* New switch management features including traffic counters and per-port promiscuous-mode.
* Xilinx platform: Added block-diagram IP-core wrappers for many functional blocks.

## v1.1.0 (2020 June)

* Added platform support for the Microsemi Polarfire.
* New features including improved MAC-address lookup, a virtual port (AXI-mailbox), SPI ports with an output clock, and improved build scripting.

## v1.0.0 (2019 December)

* Initial release of the SatCat5 mixed-media Ethernet switch.
* Supported FPGA platforms: Lattice iCE40, Xilinx 7-Series
* Supported Ethernet interfaces: RMII, RGMII, SGMII, SPI, UART
* Also included: Example designs for the Arty A7 as well as several [custom boards](../test/proto_pcb/README.md), the [PiWire](../test/pi_wire/readme.md) adapter software, a Python-based mixed-media-Ethernet [chatroom demo](../test/chat_client/README.md), and Jenkins scripts for continuous integration and testing.

# Copyright Notice

Copyright 2019-2024 The Aerospace Corporation

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
