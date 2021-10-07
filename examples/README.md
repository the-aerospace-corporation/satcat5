# SatCat5 Example Designs

![SatCat5 Logo](../doc/images/satcat5.svg)

The "examples" folder contains example designs for specific FPGA development kits.

This README gives a brief description of each example design.

# ac701_loopback

Target: Xilinx AC701 standalone design

Loopback SGMII testing for Xilinx AC701, using the built-in SMA ports.  Provides metrics for signal-integrity testing.

# ac701_proto_v1

Target: Xilinx AC701 + Custom I/O board

A family of example designs for the Xilinx AC701 dev-kit coupled to a [custom FMC I/O board](ac701_proto_v1/proto_pcb/README.md).
The I/O board includes an Ethernet switch ASIC, PMOD ports for Ethernet-over-SPI/UART, and gigabit Ethernet PHYs.
Variants are provided using RMII, RGMII, and SGMII interfaces.

# ac701_router

Target: Xilinx AC701 + Avnet Network FMC

This design hosts a three-port IPv4 router on the AC701, using an off-the-shelf FMC card with two additional Ethernet PHYs (RGMII).
It also showcases the use of SatCat5 IP-core wrappers in the Vivado block diagram tool.

# arty_a7

Target: Digilent Arty A7-35T or A7-100T

This design hosts a SatCat5 Ethernet switch that connects the Arty's built-in RJ45 port to the four PMOD ports.
Each PMOD port acts as an auto-sensing Ethernet-over-SPI/UART port.

# arty_managed

Target: Digilent Arty A7-35T or A7-100T

This design is similar to "arty_a7", but with a managed SatCat5 Ethernet switch and a built-in Microblaze processor.
It also showcases the use of SatCat5 IP-core wrappers and the SatCat5 embedded software libraries.

# ice40_hx8k

Target: Lattice iCE40-HX8K

This design acts as a passthrough converter, connecting the RJ45 port to a single SPI/UART port.

# mpf_splash

Target: Microsemi MPF-Splash + Xilinx XM105 breakout

This design hosts a SatCat5 Ethernet switch that connects the PolarFire's built-in RJ45 port to three Ethernet-over-SPI/UART ports on the breakout board.

# proto_v2

Target: Custom prototype with a Xilinx Artix FPGA.

A larger example design with a SatCat5 Ethernet switch connecting one Ethernet PHY, four SGMII ports, and eight SPI/UART ports.

# zed_converter

Target: Avnet ZedBoard

This design connects the Zynq PS Ethernet port to a PMOD Ethernet-over-SPI/UART port.

# Copyright Notice

Copyright 2021 The Aerospace Corporation

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
