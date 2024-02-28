# ZCU208 Clock Synthesizer Config Tool

The ZCU208 Clock Synthesizer is an example design for SatCat5.
The design uses the ZCU208 RF data converters to synthesize a 125 MHz sine
wave.  Using a vernier phase locked loop operating in the DAC clock domain,
the synthesized sine wave is phase-locked to an external 125 MHz reference.

The console application in this folder is used to configure the ZCU208 and
its attached CLK104 mezzanine card.

# Building

Once all prerequisites are installed, run "make run".

# Usage

Run "config_tool.bin [uart_name]",
where uart_name is the name of a USB-UART attached to the ZCU208.
(e.g., Something similar to "COM4" on Windows or "/dev/ttyusb0" on Linux.)

# Copyright Notice

Copyright 2023 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
