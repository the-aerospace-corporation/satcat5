# SatCat5 Arty A7 Example Design

![SatCat5 Logo](images/satcat5.svg)


# Overview

We provide an example design for the
[Digilent Arty A7 board](https://reference.digilentinc.com/reference/programmable-logic/arty-a7/start)
that can be used with the Python chat app or your own code to try out SatCat5.

The design provides four UART ports on the PMOD connectors, one 10/100Mbps Ethernet port
connected to the FPGA MAC over RMII, and a status LCD interface on the ChipKit IOs.


# Building

The design has been tested on both Arty A7 35T and 100T variants with Vivado 2015.4, 2016.1, 2018.2, 2018.3, or 2019.1.
Follow these steps to build the design and deploy to your Arty A7 board.

1. Obtain and install [Digilent board files](https://reference.digilentinc.com/vivado/installing-vivado/start) for Vivado.
1. Launch the Vivado GUI.
1. From the Vivado TCL shell:
    * Navigate to the SatCat5 folder. e.g., `cd path/to/satcat5`
    * Run either `set argv 35t` or `set argv 100t` to select the appropriate hardware variant.
    * Then run the following commands:
        ```bash
        cd examples/arty_a7
        source create_project_arty_a7.tcl
        ```
1. Connect an ethernet cable and up to 4 USB-UART cables (or Digilent PMOD USB-UART adapters) to the board and PC.
If using 2-wire UART tie the `CTSb` line (pin 1) of each port to ground (pin 5).
1. Open jumper JP1 to load bitstream with JTAG and program the device in Vivado.
The `.bin` files generated in `examples/arty_a7/backups` can also be used to program the SPI flash.

## Notes
* When using a design stored on the SPI flash, you may need to press the reset button after powering the board if power is applied through the micro-USB header.

# Running the Chat Demo

1. Once the board has been connected and programmed as described above, follow the readme in `test/chat_client` to install dependencies for the chat demo.
1. Run the chat demo with `python3 chat_client.py`, selecting the configuration and status UART (provided over the micro-USB programming cable) and your UART PMOD and ethernet ports.
1. Enjoy testing SatCat5 performance!

## Notes
* The UART ports are fixed at 921,600 baud by default in the example design and the ethernet link operates at 100Mbps unless forced to 10Mbps by lowering `GPO_RMII_FAST` in `switch_cfg.py`.
* The `RESET` button may be pressed to reset the switch logic and ethernet PHY without reloading device configuration.


# Copyright Notice

Copyright 2019-2023 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
