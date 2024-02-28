# ConfigBus

![SatCat5 Logo](images/satcat5.svg)

## What is ConfigBus?

[ConfigBus](../src/vhdl/common/cfgbus_common.vhd) is a simple
memory-mapped interface for configuration registers.  This interface
is used for configuring a variety of SatCat5 building blocks.

The design is optimized for simplicity over throughput.  A single "host"
issues commands on a shared bus with up to 256 peripherals.  Responses
from all attached peripherals are OR'd together to minimize required
FPGA resources.

Each peripheral may have up to 1024 registers of 32-bits each.
(This size matches 4 kiB cache-line sizes on many common processors,
and it's large enough to memory-map a complete Ethernet frame.)
Each peipheral has a unique device address (set with DEVADDR generic).

All ConfigBus hosts and peripherals are platform-agnostic, and can be found in
[the VHDL common source folder](../src/vhdl/common/). As with most of the
repository, each block is well documented in code comments at the start of the
file. On Xlinx platforms, it may be convenient to configure ConfigBus hosts and
peripherals using the supported [IP Integrator flow](IPI_FLOW.md).

## ConfigBus Hosts

ConfigBus can be controlled through several interfaces using the
provided HDL adapter blocks.

### Memory-Mapped

AXI4 is a memory-mapped interface that is ubiquitous in ARM microprocessors,
as well as soft-core microcontrollers. If your design contains a microprocessor
or microcontroller, hard IP or soft-core, you will most likely want to
use an [AXI4 adapter](../src/vhdl/common/cfgbus_host_axi.vhd). Note that this
block strongly recommends using the full 20 bits of AXI address space (1MiB)
to ensure access all possible registers.

### Streaming

ConfigBus can also be attached directly to a
[virtual Ethernet port](../src/vhdl/common/port_cfgbus.vhd).
Use this type of adapter if control of your system should be through a
trusted Ethernet LAN. This host operates only on raw Ethernet frames for
simplicity, and as a result does not need a microcontroller or microprocessor
in the system. Thus, this host is an excellent method to perform low-throughput
FPGA command and control fom an external host. An example configuration can be
found in the [IP Integrator Flow](IPI_FLOW.md) documentation.

The host controller's MAC address and the ethertype for ConfigBus packets are
set by the module generics (or [IPI configuration](IPI_FLOW.md)).
Send a frame to the designated MAC address to execute read or write commands;
refer to [comments in the HDL](../src/vhdl/common/cfgbus_host_eth.vhd)
for further details on packet formatting.
[C++ software drivers](../src/cpp/satcat5/cfgbus_remote.h)
for this protocol are provided and are compatible with the POSIX HAL.
[Python software drivers](../src/python/satcat5_cfgbus.py)
are also provided and use [Scapy](https://scapy.net) as the backend.

The same command set can also be
[sent over UART](../src/vhdl/common/cfgbus_host_uart.vhd)
via a SLIP-encoded commands of the same format. Both the C++ and Python
software driver stacks are also compatible with the UART host. This is the
simplest interface to configure, requiring instantiation of a single VHDL
module with just clock, reset, UART, and ConfigBus ports.

## ConfigBus Peripherals

The majority of provided ConfigBus modules are peripherals. They can be found
in the [VHDL common sources](../src/vhdl/common/) directory. Each module has
its own set of registers and protocol for mapping ConfigBus reads and writes to
its own protocol. Details on each moule's pprotocol can always be found in the
comments at the top of the source file.

The following peripherals are available for use.
Peripherals are added frequently, so this list is not exhaustive.

- Ethernet frame send/receive (MailBox and MailMap)
- I<sup>2</sup>C controller
- SPI controller
- LED controller with PWM
- MDIO controller
- 16x2 LCD character display controller
- Multi-purpose CPU and watchdog timer
- UART

### What are MailBox and MailMap?

These are virtual Ethernet ports that allow an embedded soft-core CPU
to send and receive Ethernet frames.  They are typically attached to
one port of an Ethernet switch on the same FPGA that hosts the CPU.

They are accessed over ConfigBus.  "MailBox" is slower but requires
fewer FPGA resources; data is read or written one byte at a time.
"MailMap" allows the entire frame to be memory-mapped into the CPU's
address space, so that it can be accessed like any other array.

We recommend using MailMap for most designs.

### Adding ConfigBus Registers to Custom Designs

ConfigBus is designed to be easy to use in new designs. Plumbing ConfigBus
through designs consists of passing the `cfgbus_cmd` and `cfgbus_ack` VHDL
record types defined in [cfgbus_common](../src/vhdl/common/cfgbus_common.vhd).
Multiple ConfigBus routes are handled gracefully - `cfgbus_cmd` signals from
the host are distributed to all peripherals and `cfgbus_ack` signals from
peripherals are merged with the `cfgbus_merge()` function. As an example, three
registers' responses can be concatenated by creating a
`signal cfg_acks: cfgbus_ack_array(2 downto 0)`,
each register drives a unique element of the array, and the responses are
flattened into one `cfgbus_ack` signal via the call
`cfg_ack <= cfgbus_merge(cfg_acks)`. Existing peripherals provide further
examples of proper usage. Note that a `cfgbus_buffer` module is also available
for ConfigBus designs that struggle to meet timing.

Several modules are provided to facilitate easy creation of control and status
registers. All can be found in
[cfgbus_common](../src/vhdl/common/cfgbus_common.vhd).
Registers can either be synchronous or asynchronous to the ConfigBus clock
domain, with both readonly and read/write register types available.

| Module                | Read?         | Write?        | Async Clocks? |
| :-------------------- | :-----------: | :-----------: | :-----------: |
| cfgbus_register       | &#9745; Yes   | &#9745; Yes   | &#9744; No    |
| cfgbus_register_sync  | &#9745; Yes   | &#9745; Yes   | &#9745; Yes   |
| cfgbus_register_wide  | &#9744; No    | &#9745; Yes   | &#9745; Yes   |
| cfgbus_readonly       | &#9745; Yes   | &#9744; No    | &#9744; No    |
| cfgbus_readonly_sync  | &#9745; Yes   | &#9744; No    | &#9745; Yes   |
| cfgbus_readonly_wide  | &#9745; Yes   | &#9744; No    | &#9745; Yes   |

Each register will have a device address (DEVADDR) and a register address
(REGADDR). Writeable registers additionally have optional write values,
reset values, and write strobes. Most use cases will need to simply need to
create one `cfgbus_word` signal per register, connect it to the `sync_val` or
`reg_val` port in the register module, and assign its bits to appropriate
control or status signals in the user design.

Please see module documentation for all available features.

# Copyright Notice

Copyright 2022 The Aerospace Corporation

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
