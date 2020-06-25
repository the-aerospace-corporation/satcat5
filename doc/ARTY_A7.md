# SatCat5 Arty A7 Example Design

![SatCat5 Logo](images/satcat5.svg)


# Overview

We provide an example design for the [Digilent Arty A7 board](https://reference.digilentinc.com/reference/programmable-logic/arty-a7/start) that can be used with the Python chat app or your own code to try out SatCat5.

The design provides four UART ports on the PMOD connectors, one 10/100Mbps ethernet port connected to the FPGA MAC over RMII, and a status LCD interface on the ChipKit IOs.


# Building

The design has been tested on both Arty A7 35T and 100T variants with Vivado 2015.4, 2018.2, or 2018.3.
Follow these steps to build the design and deploy to your Arty A7 board.

1. Obtain and install [Digilent board files](https://reference.digilentinc.com/vivado/installing-vivado/start) for Vivado
1. From `project/vivado_2015.4` create and build the project with either of the methods below (examples for 100T variant).
    * From the terminal, run
        ```
        vivado -mode batch -nojournal -nolog -notrace -source create_project_arty_a7.tcl -tclargs 100T
        vivado -mode batch -nojournal -nolog -notrace -source build_arty_a7_rmii.tcl -tclargs 100T
        ```
    * From the Vivado GUI, run `set argv 100T` then `source ./create_project_arty_a7.tcl` and use the GUI to generate the bitstream.
1. Connect an ethernet cable and up to 4 USB-UART cables (or Digilent PMOD USB-UART adapters) to the board and PC.
If using 2-wire UART tie the `CTSb` line (pin 1) of each port to ground (pin 5).
1. Open jumper JP1 to load bitstream with JTAG and program the device in Vivado.
The `.bin` files generated in `project/vivado_2015.4/backups` can also be used to program the SPI flash.

## Notes
* When using a design stored on the SPI flash, you may need to press the reset button after powering the board if power is applied through the micro-USB header.

# Running the Chat Demo

1. Once the board has been connected and programmed as described above, follow the readme in `test/chat_client` to install dependencies for the chat demo.
1. Run the chat demo with `python3 chat_client.py`, selecting the configuration and status UART (provided over the micro-USB programming cable) and your UART PMOD and ethernet ports.
1. Enjoy testing SatCat5 performance!

## Notes
* The UART ports are fixed at 921,600 baud by default in the example design and the ethernet link operates at 100Mbps unless forced to 10Mbps by lowering `GPO_RMII_FAST` in `swtich_cfg.py`.
* The `RESET` button may be pressed to reset the switch logic and ethernet PHY without reloading device configuration.


# Copyright Notice

Copyright 2019 The Aerospace Corporation

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
