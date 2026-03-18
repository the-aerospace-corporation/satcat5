# SatCat5 Change Log

![SatCat5 Logo](images/satcat5.svg)

This log will be updated for each new release, but may not reflect the latest development branch(es).

## v2.9.0 (2026 March)

* Added a ConfigBus emulator for the eth::SwitchConfig driver.
* Added an IGMP software client and server, with tweaks to gateware IGMP multicast handling.
* Added GitHub Copilot Agent file to help onboard new developers to C++ software stack.
* Added PCAP support to the Python APIs for CCSDS, Ethernet, and SLIP.
* Added port::BufferAdapter is a drop-in replacement for NullAdapter, but with VLAN support.
* Added support for SGMII rate auto-negotitation via TX_CFG_REG for PHYs as an alternative to auto-detection.
* Fixed a bug in cfg::Hdlc that could deadlock data_rcvd() notifications.
* Fixed an illegal use of IDELAYE3 on clock input signals.
* Fixed issues with SGMII repetition (10M/100M modes).
* Fixed GPS epoch conversion in PTP software stack.
* Fixed MAC learning issue after switch reset.
* Fixed NTP header leap-seconds value preventing usage by some client implementations.
* Fixed Polarfire DDR I/O IP core generation.
* Fixed software switch control when priority ethertypes are disabled.
* Improved Polarfire SGMII clock distributed via shared-clock chaining mechanism.
* Improved PTP ANNOUNCE message handling with log-variance estimation and clockIdentify fix.

## v2.8.0 (2025 October)

* Added coarse options for PTP clock-crossing (less precise, more robust).
* Added gateware and software support for Constant Overhead Byte Stuffing (COBS).
* Added Python support for CCSDS-AOS and CCSDS-SPP.
* Fixed formatting of NTP-related UDP headers.
* Fixed handling of certain CCSDS-AOS edge cases.
* Fixed statistics reporting for Ethernet ports with a stopped clock.
* Fixed unsafe handling of destructors when "SATCAT5_ALLOW_DELETION=0". (Replaces undefined behavior with an intentional deadlock/halt.)
* Fixed various bugs in the SAM V71 hardware abstraction layer.
* Improved control over PTP message rates and UTC offset.
* Improved logging functions, including log-forwarding.
* Improved PTP-locked synthesizers with runtime-adjustable frequency (e.g., PPS, 10 MHz).
* Split net::Socket class into Rx-only and Tx-only variants.
* Update included QCBOR to v1.5.2, bug-fixes for associated SatCat5 wrappers.

## v2.7.0 (2025 August)

* Added support for CoAP reverse-proxy.
* Added support for HDLC (physical layer only).
* Added support for RTTTL (legacy ringtone format).
* Completed Doxygen rollout to 100% of C++ files.
* Fixed edge-cases in CCSDS-AOS and CCSDS-SPP decoders.
* Fixed standards-compliance of UART flow-control signals.
* Improved support for complex CBOR data structures.
* Improved support for FreeRTOS and the SAM V71 microcontroller.
* New diagnostics for switches and routers, including reason why a given frame was dropped.
* New multi-mode UART toggles between raw, CCSDS-AOS, CCSDS-SPP, and SLIP mode.
* Software packet capture now supports multiple interfaces.
* Software router now supports basic network address translation (NAT).
* Split the ALLOW_RUNT parameter into separate parameters ALLOW_RUNT_IN, ALLOW_RUNT_OUT.

## v2.6.0 (2025 January)

* Added client/server for the Constrained Applications Protocol (CoAP)
* Added client/server for the Network Time Protocol (NTP)
* Added support for Doppler-PTP (an experimental extension to PTP)
* Added support for Simple-PTP (Meta's client-initiated PTP variant)
* Create a gateware-defined CIDR-capable IPv4 router supporting multiple gigabit-rate ports.
* Create a software-defined Ethernet switch, to augment or replace the FPGA-defined switch.
* Create a software-defined IPv4 router, for support/offload or low-rate standalone applications.
* Improved support for the Microchip Polarfire-FPGA and Polarfire-SoC platforms.
* Initial integration of Doxygen documentation. Limited coverage for now.
* More options for PTP filtering and control logic.
* More options for Readable and Writeable formats (s24, s48, u24, u48).
* New hardware abstraction layers for FreeRTOS and the Microchip SAM V71.
* Replace "GenericTimer" with the new and improved "TimeRef" API.
* Virtual PCAP mode for improved unit test diagnostics.

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
* Example designs for the Arty A7 and [a custom FMC board](../examples/ac701_proto_v1/proto_pcb/README.md).
* [PiWire](../test/pi_wire/readme.md) mixed-media Ethernet bridge.
* Python [chatroom demo](../test/chat_client/README.md) for mixed-media Ethernet.

# Copyright Notice

Copyright 2019-2025 The Aerospace Corporation

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
