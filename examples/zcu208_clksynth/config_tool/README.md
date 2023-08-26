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

Copyright 2023 The Aerospace Corporation

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
along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
