# SatCat5 Example Designs

![SatCat5 Logo](../doc/images/satcat5.svg)

The "examples" folder contains example designs for specific FPGA development kits.

This README gives a brief description of each example design.

# ac701_loopback

Target: [Xilinx AC701](https://www.xilinx.com/products/boards-and-kits/ek-a7-ac701-g.html) standalone design

Loopback SGMII testing for Xilinx AC701, using the built-in SMA ports.  Provides metrics for signal-integrity testing.

# ac701_proto_v1

Target: [Xilinx AC701](https://www.xilinx.com/products/boards-and-kits/ek-a7-ac701-g.html) + [Custom I/O board](./ac701_proto_v1/proto_pcb/README.md)

A family of example designs for the Xilinx AC701 dev-kit coupled to a [custom FMC I/O board](ac701_proto_v1/proto_pcb/README.md).
The I/O board includes an Ethernet switch ASIC, PMOD ports for Ethernet-over-SPI/UART, and gigabit Ethernet PHYs.
Variants are provided using RMII, RGMII, and SGMII interfaces.

# ac701_router

Target: [Xilinx AC701](https://www.xilinx.com/products/boards-and-kits/ek-a7-ac701-g.html) + [Avnet Network FMC](https://www.avnet.com/shop/us/products/avnet-engineering-services/aes-fmc-netw1-g-3074457345635205181/)

This design hosts a three-port IPv4 router on the AC701, using an off-the-shelf FMC card with two additional Ethernet PHYs (RGMII).
It also showcases the use of SatCat5 IP-core wrappers in the Vivado block diagram tool.

# arty_a7

Target: [Digilent Arty A7-35T or A7-100T](https://digilent.com/reference/programmable-logic/arty-a7/start)

This design hosts a SatCat5 Ethernet switch that connects the Arty's built-in RJ45 port to the four PMOD ports.
Each PMOD port acts as an auto-sensing Ethernet-over-SPI/UART port.

# arty_managed

Target: [Digilent Arty A7-35T or A7-100T](https://digilent.com/reference/programmable-logic/arty-a7/start)

This design is similar to "arty_a7", but with a managed SatCat5 Ethernet switch and a built-in Microblaze processor.
It also showcases the use of SatCat5 IP-core wrappers and the SatCat5 embedded software libraries.

# ice40_hx8k

Target: [Lattice iCE40-HX8K](https://www.latticesemi.com/en/Products/DevelopmentBoardsAndKits/iCE40HX8KBreakoutBoard.aspx)

This design acts as a passthrough converter, connecting the RJ45 port to a single SPI/UART port.

# mpf_splash

Target: [Microsemi MPF-Splash](https://www.digikey.com/en/products/detail/microchip-technology/MPF300-SPLASH-KIT/10269026) + [Xilinx XM105 breakout](https://www.xilinx.com/products/boards-and-kits/hw-fmc-xm105-g.html)

This design hosts a SatCat5 Ethernet switch that connects the PolarFire's built-in RJ45 port to three Ethernet-over-SPI/UART ports on the breakout board.

# netfpga_managed

Target: [Digilent NetFPGA-1G-CML](https://digilent.com/reference/programmable-logic/netfpga-1g-cml/reference-manual)

This design contains a managed SatCat5 Ethernet switch that links the board's four RJ45 jacks and the two PMOD ports (as Ethernet-over-SPI/UART).
It also contains a Microblaze processor and several ConfigBus peripherals.

# proto_v2

Target: Custom prototype with a Xilinx Artix FPGA.

A larger example design with a SatCat5 Ethernet switch connecting one Ethernet PHY, four SGMII ports, and eight SPI/UART ports.

# python

Target: Not applicable

This folder contains software examples for the Python API.

# slingshot

Target: [Slingshot-1 cubesat](https://aerospace.org/article/slingshot-platform-fast-tracks-space-systems-using-modularity-and-open-standards)

This folder contains interface control documents (ICDs) for the Slingshot modular interface.
Slingshot uses SatCat5 to link together any number of smallsat payloads on a spacecraft LAN.

# vc707_clksynth

Target: [Xilinx VC707 development board](https://www.xilinx.com/products/boards-and-kits/ek-v7-vc707-g.html)

This design is a demo used to verify performance of the Vernier-PLL system.
That system, defined in "ptp_counter_gen" and "ptp_counter_sync", generates a synchronized counter in different clock domains.
In other example designs, the system is used to measure delay for PTP transparent clock mode.
In this demo, it is used to synthesize a 25 MHz square wave from four different clock domains.

# vc707_managed

Target: [Xilinx VC707 development board](https://www.xilinx.com/products/boards-and-kits/ek-v7-vc707-g.html)

This design is similar to "arty_managed".
It contains a SatCat5 Ethernet switch that connects the RJ45 port, the SFP port, and the USB-UART.
It also contains a Microblaze processor and several ConfigBus peripherals.

Note that this design requires the "AVB" license for the Xilinx TEMAC IP-core, due to the use of PTP features.

# zcu208_clksynth

Target: [Xilinx ZCU208 development board](https://www.xilinx.com/products/boards-and-kits/zcu208.html)

Like the "vc707_clksynth" demo, this example design is used to verify performance of the Vernier-PLL system.
In this demo, a Vernier-PLL is used to synthesize a 125 MHz sine wave.
Use of sine waves instead of discrete-sampled square waves avoids discrete-time quantization error.
In theory, this allows accuracy and jitter measurements on picosecond time-scales.

# zed_converter

Target: [ZedBoard Zynq-7000 Development Board](https://digilent.com/reference/programmable-logic/zedboard/start)

This design connects the Zynq PS Ethernet port to a PMOD Ethernet-over-SPI/UART port.

# Copyright Notice

Copyright 2021, 2022, 2023 The Aerospace Corporation

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
