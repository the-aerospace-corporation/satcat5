## SatCat5 Software

![SatCat5 Logo](images/example_network.svg)

### What software is provided?

SatCat5 includes [C++ software libraries](../src/cpp/README.md) for:

* Sending and receiving Ethernet frames over nearly any interface.
* Sending and receiving ARP, ICMP, IP, and UDP messages.
* Configuring a managed SatCat5 Ethernet switch.
* Configuring various SatCat5 I/O peripherals (e.g., I2C, MDIO, SPI, or UART).

SatCat5 also includes [Python software libraries](../src/python) for some of these functions.

### How do I use the C++ software?

The [core functions](../src/cpp/satcat5) are as generic as possible,
designed for use on bare-metal microcontrollers, FreeRTOS, Linux, or Windows.
We provide hardware abstraction layers for several of these platforms.

Since many of these platforms are extremely constrained (64 kiB RAM or less),
the design has minimal dependencies (even printf is too large) and all objects
can be statically allocated.  Heap allocation is not used in the core, but
is an option in hardware abstraction layers intended for desktop platforms.

For more information, [refer to the README](../src/cpp/README.md).

### Why do you have a UDP network stack?

SatCat5 is intended for use on tiny microcontroller and unconventional
interfaces, like SPI and UART.  Very few operating systems allow the
required level of customization, so we built a simple stack from scratch.

SatCat5 does not currently support TCP/IP, but may add lwIP support in a future release.

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
along with SatCat5.  If not, see [https://www.gnu.org/licenses/](https://www.gnu.org/licenses/).
