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

Copyright 2021 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
