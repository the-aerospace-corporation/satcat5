# SatCat5 Embedded C++ Library

This folder defines embedded C++ software for use with SatCat5.

The bulk of this software is for controlling various ConfigBus peripherals.
However, there are also a framework for other useful features, including:
* Handling of prompt and deferred interrupts
* Polling and timers
* Diagnostic logging
* Network stack for Ethernet, ARP, IP, ICMP, and UDP protocols
* Ordinary and packetized buffers
* SLIP encoder and decoder
* Various general-purpose utility functions

To the extent possible, the code is platform-agnostic and amenable to implementation on microcontrollers.
As such, memory-footprint is assumed to be extremely limited, and there is no heap memory allocation.
Where necessary, hardware abstraction layers are used for cross-platform support.
This includes stubs and helper functions used for unit-testing.

# Using these libraries

We've tried to make it easy to use these libraries on nearly any platform, embedded or otherwise.

There are three key steps:
* Create an instance of each applicable driver object.
* Call the `init()` method for the interrupt handler of choice.  (See "Hardware Abstraction Layer")
* Call the `satcat5::poll::service()` function at regular intervals.

If you use any `satcat5::poll::Timer` object, you must also call `satcat5::poll::timekeeper.request_poll()`
once every millisecond.  (See also: `irq::Adapter`, `irq::VirtualTimer`)

In an embedded environment, instances should be statically allocated as global variables.
The service() function can then be called from inside your main loop.

Here is an example for the Xilinx Microblaze:

    #include <hal_ublaze/interrupts.h>
    #include <satcat5/polling.h>
    #include <xparameters.h>

    XIntc irq_xilinx;
    satcat5::irq::ControllerMicroblaze irq_satcat5(&irq_xilinx);

    void main() {
        irq_satcat5.irq_start(XPAR_UBLAZE_CORE_MICROBLAZE_0_AXI_INTC_DEVICE_ID);
        while (1) satcat5::poll::service();
    }

On a POSIX system, driver instances can be created on the stack or on the heap.
However, the same rules apply: create your objects, then call service() frequently.

# Important concepts

## Readable and Writeable

These abstract classes define basic I/O operations on a byte-stream.
They are defined in "satcat5/io_core.h" and used throughout the SatCat5 software libraries.

"Readable" is the parent object for anything that consumes data from a byte-stream.
"Writeable" is the parent object for anything that appends data to a byte-stream.
Some classes, such as the PacketBuffer in "satcat5/pkt_buffer.h", inherit from both.
i.e., You can pass a PacketBuffer pointer as either Readable or Writeable.

Methods are provided for reading and writing common data-types.
Each such field is always read or written in "network order" (big-endian).

## ConfigBus

ConfigBus is a memory-mapped interface that's used to configure most SatCat5 peripherals.
Each control register is a uint32_t that is read or written atomically.

Register addresses are defined at build-time, as part of the FPGA design.
A given peripheral may be allocated a single register,
or a "device address" indicating a bank of up to 1,024 registers.

At present, the address constants for a given peripheral must be defined and cross-checked manually.

In the embedded context, ConfigBus read/writes usually map to pointers in the local memory space.
In such cases, defining "SATCAT5_CFGBUS_DIRECT" reduces all ConfigBus I/O to simple pointers.
When applicable, this can result in significant performance and code-size improvements.

However, we also provide tools for controlling ConfigBus devices over a network interface,
or for accepting that type of network control packet.
The same interface is also used for unit tests against simulated peripherals.
The WrappedRegister class is designed to allow all such interactions with pointer-like syntax,
allowing compilation in either mode with no changes to the source code of each driver.
If any of these features are used, do not define "SATCAT5_CFGBUS_DIRECT".

## GenericTimer

Many network and peripheral control functions need to measure the passage of time.
The "GenericTimer" (satcat5/timer.h) is the fundamental building block for these functions.

Linux-based designs should create a global PosixTimer object (hal_posix/posix_utils.h),
which uses the system time (CLOCK_MONOTONIC, if available, with fallback to "clock()").

FPGA-based designs may create a global ConfigBus timer object (satcat5/cfgbus_timer.h),
which reads from the corresponding ConfigBus peripheral defined in the FPGA design.

If you don't have a ConfigBus timer, create your own by inheriting from GenericTimer
and providing a monotonically increasing uint32_t counter.

## Network stack

Most SatCat5 network protocols can be operated in raw-Ethernet mode or UDP mode.
The network API is designed to facilitate this type of stack-agnostic operation.

The two key classes are "net::Dispatch" and "net::Protocol" (satcat5/net_core.h).
Each is an abstract class with definitions for Ethernet, IP, UDP, etc.

Each Dispatch object listens for incoming data, reads the frame header,
then routes the remaining data to a matching Protocol.

Consider an example with a typical UDP stack:

    * An incoming Ethernet frame is delivered to eth::Dispatch.
    * eth::Dispatch reads the Ethernet header (Dst+Src+Type) with Type = 0x0800 (IPv4).
    * eth::Dispatch scans its list of Protocol objects, and finds a match.
    * ip::Dispatch reads the IP header with Proto = 0x11 (UDP).
    * ip::Dispatch scans its list of Protocol objects, and finds a match.
    * udp::Dispatch reads the UDP header with Port = 0x1234.
    * udp::Dispatch scans its list of Protocol objects...

In this example, ip::Dispatch is both a Protocol (for matching EtherType) and a Dispatch (for reading the IP header).

Here is an example of a complete UDP stack:

    satcat5::port::Mailmap      eth_port(&cfgbus, DEVADDR_MAILMAP);
    satcat5::eth::Dispatch      net_eth(LOCAL_MAC, &eth_port, &eth_port);
    satcat5::ip::Dispatch       net_ip(LOCAL_IP, &net_eth, &timer);
    satcat5::udp::Dispatch      net_udp(&net_ip);

## Other tips

If you're looking for something, check "satcat5/types.h".
It contains a prototype for nearly every important class,
with comments indicating where to find the full definition.

# Folder structure

The folder containing this README should be added to the compiler's INCLUDE path.
All .h files are placed in subfolders so that the include directive reads as "#include<satcat5/xyz.h>".

The "satcat5" folder, plus each HAL that you would like to use (see below) should be added to the compiler's SOURCE path.
Adding the parent folder and ignoring unused folders is not recommended, as new HAL folders are added regularly.

Prototypes for the most commonly used classes are defined in "satcat5/types.h".
Each one includes a comment noting the location of the full class definition.

# Hardware abstraction layers

Code that cannot be made cross-platform is moved to a separate "Hardware Abstraction Layer" (HAL).
This allows us to support platform-specific functionality, remote control over a network, and many other features.

Currently supported platforms include:
* hal_devices: Device drivers for specific peripheral devices.
* hal_pcap: Adapter for connecting PCAP/NPCAP to a SatCat5 stream (Win/Linux).
* hal_posix: Utility functions for POSIX-compatible systems (e.g., GNU/Linux)
* hal_test: A simulated environment for unit-testing of ConfigBus drivers (Win/Linux).
* hal_ublaze: Hardware support for the Xilinx Microblaze family of soft-core CPUs.

Many other configuration parameters can be set using the "-D" compiler directive.

For example, consider an application that uses only global objects that will never fall out of scope.
In this case, consider setting "SATCAT5_ALLOW_DELETION=0" to disable code-generation for those destructors.
This can save several kilobytes of code-space.

Many embedded systems should also set "SATCAT5_CFGBUS_DIRECT=1" to minimize code size.

# QCBOR library

The "qcbor" folder contains Laurence Lundblade's
[QCBOR library](https://github.com/laurencelundblade/QCBOR).
It is derived from version 1.2, but with a flattened folder structure,
no support code, and minimal compatibility fixes for specific compilers.

QCBOR is redistributed alongside SatCat5 under the terms of its
[open-source license](qcbor/README.md),
which is essentially the 3-clause BSD license.

The QCBOR library is used for encoding of CBOR key-value dictionaries as part of the 
`eth::Telemetry` and `udp::Telemetry` classes; see satcat5/net_telemetry.h" for details.

To use this library, set the following compiler options:
* SATCAT5_CBOR_ENABLE=1 (required to use CBOR-related features)
* QCBOR_DISABLE_FLOAT_HW_USE (recommended for embedded platforms)
* QCBOR_DISABLE_PREFERRED_FLOAT (drop support for half-precision floats)

# Unit tests

Unit tests for many functions are [included here](../../sim/cpp).
We attempt to maintain 100% code-coverage of all files in the "src/cpp/satcat5" subfolder.

These tests use the open-source ["Catch2" library](https://github.com/catchorg/Catch2),
which is redistributed under the terms of the Boost license.

# Copyright Notice

Copyright 2021-2023 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
