# Files in this folder

![SatCat5 Logo](../../doc/images/satcat5.svg)

The design files in this folder are for a custom PCB that is designed to attach to an FMC (FPGA Mezzanine Card) connector.  HPC variants are preferred, but LPC is also supported with reduced functionality.  All I/O is either LVDS or 2.5LVCMOS.

The design is compatible with the following dev cards:
* [Xilinx AC701](https://www.xilinx.com/products/boards-and-kits/ek-a7-ac701-g.html)
* [Microsemi Polarfire Splash](https://www.microsemi.com/existing-parts/parts/144001)

The .PCB file was created using MentorGraphics PADS. A viewer can be [downloaded from MentorGraphics](https://www.pads.com/downloads/pads-pcb-viewer/) free of charge (registration required).

# IMPORTANT NOTE

These files are for the as-built prototype design, dated 2018 December 12.
The schematic has not been updated to reflect problems that were discovered after manufacture.

As a result, the following fixes are required:
* Replace linear regulators U9 and U10 with 3.3V equivalent. (Wrong voltage.)
* Replace C73, C74, C173, C174 with 0-ohm resistor. (Xilinx LVDS inputs are not self-biasing.)

These changes have been made on the BOM, but not on the schematic.

![Photo of the prototype](../../doc/images/prototype.jpg)

# Copyright Notice

Copyright 2019 The Aerospace Corporation

All files in this folder are part of SatCat5.

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
