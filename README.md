# SatCat5 Introduction

![SatCat5 Logo](doc/images/satcat5.svg)

SatCat5 is FPGA gateware that implements a low-power, mixed-media Ethernet switch.
It also includes embedded software libraries to help microcontrollers interact with Ethernet networks.

A SatCat5 switch is functionally equivalent to commercially available, unmanaged Ethernet switches for home use.
However, it also supports lower-speed connections to the same network using I2C, SPI, or UART.
These lower-rate data links (commonly used in simple, low-cost, low-power microcontrollers)
allow nearly any device to participate in the same local communication network, regardless of its capability level.

Like any Ethernet switch, this one has multiple ports; each port is a point-to-point link from
the switch to a network device, which could be a PC, a microcontroller, or even another switch.
Power draw required for the switch itself is well under 1 watt.

The main expected users of this project are cubesat and smallsat developers.
By encouraging everyone to use this technology, we create a mutually-compatible ecosystem that will make it easier
to develop new small-satellite payloads, and simultaneously make it easier to integrate those payloads into vehicles.
For more information on SatCat5 and cubesats, refer to [our SmallSat 2020 publication](https://digitalcommons.usu.edu/smallsat/2020/all2020/174/). However, we think the same technology might be useful to other embedded systems,
including Internet-of-Things systems that want to integrate microcontrollers onto a full-featured LAN.

# Switch Capabilities

![Example network with microcontrollers and other nodes](doc/images/example_network.svg)

A major goal of the SatCat5 project is to support a variety of endpoints, from simple
microcontrollers to a full-fledged PC, all connected to the same Ethernet network.

A complete listing of supported interfaces is [available here](doc/INTERFACES.md).
The list includes the usual 10/100/1000 Mbps "Media Independent Interfaces"
(RMII, RGMII, SGMII) as well as media and physical-layer options that aren't
usually used with Ethernet (I2C, SPI, UART).
The latter options are typically lower speed (1-10 Mbps), but use physical layer
protocols that are more amenable to use with simple microcontrollers.
All interfaces transmit and receive standard Ethernet Frames.

Switch operation can be designed in an HDL-only environment - however, many designs use
soft-core embedded processors to provide higher level functionality such as handling of
ARP, ICMP, IP, and UDP messages, along with switch or attached device configuration.

# What Is Provided

This project is effectively a set of building blocks, ready to be used to build and connect to your own custom Ethernet switch.
The switch can be optimized to your needs, tailored to your preferred platform, port count, interface types, etc.

In addition to these building blocks, we include several
[reference designs](examples/) that showcase many of the available features.
The easiest way to get started is with the
[Digilent Arty A7](https://store.digilentinc.com/arty-a7-artix-7-fpga-development-board-for-makers-and-hobbyists/),
a low-cost FPGA development board. We've included a reference design and
[companion documentation](doc/ARTY_A7.md) that specifically targets this board.
PMOD connector pinouts are chosen to be directly compatible with off-the-shelf USB-UART adapters.

Other reference designs include the [prototype](doc/images/prototype.jpg) that we built to develop, test, and demonstrate the SatCat5 switch.
It is intended to run on many off-the-shelf FPGA development boards, using an FMC port to attached to a [custom PCB](test/proto_pcb).
The custom PCB includes Ethernet transceivers, PMOD connectors, and other I/O.

SatCat5 also includes [software libraries](src/cpp/README.md) targeting both baremetal and
POSIX systems for:

* Sending and receiving Ethernet frames.
* Sending and receiving ARP, ICMP, IP, and UDP messages.
* Configuring a managed SatCat5 Ethernet switch.
* Configuring various SatCat5 I/O peripherals (e.g., I2C, MDIO, SPI, or UART).

A simple memory-mapped interface for configuration registers called [ConfigBus](doc/CONFIGBUS.md)
was designed and can be found in the majority of designs. It is much lighter weight than AXI4-Lite
as it is designed for small control registers. More information, including Microblaze libraries,
control over Ethernet, and user register setup can be found in [its documentation](doc/CONFIGBUS.md).

# Getting Started

If you'd like to build the Arty example design, you'll need the [Vivado Design Suite](https://www.xilinx.com/products/design-tools/vivado.html).
We've tested with version 2015.4, 2016.3, and 2019.1, but it should work as-is with most other versions as well.
Once it's installed, simply run "make arty_35t" in the root folder. (Or follow the equivalent steps under Windows.)

If you'd like to build your own design, create a new top-level VHDL file and add the following:

* Any number of port_xx blocks. (e.g., port_spi, port_uart, port_rgmii, etc.)
* At least one switch_core block.
* One switch_aux block. This provides error-reporting, status LEDs, and other niceties.
* Clock generation. Check the documentation for selected port type(s) to see what's needed.

Another option for user designs on Xilinx platforms is the
[Vivado IP Integrator](doc/IPI_FLOW.md). SatCat5 natively supports this block-diagram based flow
and offers wrappers for the vast majority of compatible blocks. The drag-and-drop nature and
single-wire bus interface connections make this a good choice for complex designs.

# Further Reading

Once started and familiar with the basics of SatCat5, it is highly recommended to read through the
[Frequently Asked Questions (FAQs)](doc/FAQ.md). This contains a huge swath of tips, guidance,
clarifications, and potential issues.

Advice and tips on good development operations (DevOps) practices, including automated and
hardware-in-the-loop testig, can also be found in the [DevOps documentation](doc/DEVOPS.md)

# Folder Structure

* doc: Documentation and associated images. All documentation is linked somewhere in this README.
* examples: [Example designs](examples/README.md) for specific hardware platforms
* project: Scripts and project files for specific vendor tools
  * libero: Building Microsemi designs in Libero. (Tested with version 12.3.)
  * modelsim: Running VHDL simulations in ModelSim. (Tested with version 10.0a.)
  * vivado: Packagine IP-cores, building, or simulating Xilinx designs in Vivado. (Tested with Vivado version 2019.1.)
  * yosis: Building Lattice designs using Yosis.
* sim: Simulation and verification of the design
  * cpp: Unit tests for the embedded software libraries.
  * matlab: MATLAB/Octave scripts used to generate certain lookup tables.
  * test: Test data for various unit-test simulations.
  * vhdl: VHDL unit tests for individual functional blocks.
* src: Source code for the core SatCat5 design
  * cpp: C/C++ software libraries targeting various platforms
    * hal_devices: Abstraction layer for specific hardware peripherals.
    * hal_pcap: Abstraction layer for interfacing with PCAP or NPCAP.
    * hal_posix: Abstraction layer for Linux and Windows PCs.
    * hal_test: Abstraction layer for simulation and testing.
    * hal_ublaze: Abstraction layer for the Xilinx Microblaze soft-CPU.
    * satcat5: Cross-platform libraries for connecting to and configuring an Ethernet network.
  * python: Python libraries for connecting to raw-Ethernet / Ethernet-over-UART ports and remote ConfigBus control.
  * vhdl: VHDL implementation of functional blocks
    * common: Location of most functional blocks, targets all platforms.
    * lattice: Platform-specific VHDL for the Lattice iCE40.
    * microsemi: Platform-specific VHDL for the Microsemi Polarfire.
    * xilinx: Platform-specific VHDL for Xilinx 7-series and Ultrascale platforms.
* test: Additional testing, including the prototype reference design
  * chat_client: A demo application that implements chatroom functions using raw Ethernet frames.
  * log_viewer: A demo application for viewing Chat/Log messages from example designs.
  * pi_wire: A tool for connecting to SatCat5 with a Raspberry Pi.
  * telem_receive: A Python tool for receiving CBOR telemetry.

# Contributing

We encourage you to contribute to SatCat5! Please check out the [guidelines here](doc/CONTRIBUTING.md) for information on how to submit bug reports and code changes.

# Changelog

A log of major changes per SatCat5 release can be found in the [Change Log](doc/CHANGELOG.md).

# Patents

Portions of SatCat5 are patented or patent-pending, e.g., US11055254B2.

In accordance with SatCat5's open-source license agreement,
we grant a royalty-free license for use of these technologies.
Refer to section 7 of the CERN-OHL-W v2 license for details.

# Copyright Notice

Copyright 2019-2024 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
