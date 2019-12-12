# Pi-Wire Read-Me

Pi-Wire is a tool that turns a [Raspberry Pi](https://www.raspberrypi.org/) into a SatCat5 adapter.  It allows a conventional Ethernet network to connect directly to a SatCat5 device, using either SPI or UART protocols.

The name is intended to indicate that the device acts as close as possible to a wire. Ideally, it simply allows every packet through, verbatim, and doesn't really act like an independent device.

The instructions below assume a Raspberry Pi 3+ running stock Raspbian (2019 July 10 build).

# Installing Pi-Wire

The easiest way to run Pi-Wire is to build it using the Raspberry Pi itself.  From the /test/pi_wire folder, compile and run using the following commands:

    make all
    sudo ./pi_wire both

(To run in SPI mode only, run `sudo ./pi_wire spi`.  To run in UART mode only, run `sudo ./pi_wire uart`.)

To have the Pi-Wire act as an standalone device, you'll need to make additional changes.  First, set the raspberry pi to a static IP address.  (i.e., Typically one that starts with 192.168.x.x.)

Next, remove the following line from /boot/cmdline.txt:

    console=serial0,115200

Next, enable the SPI and UART ports.  Copy the provided "config.txt" file to /boot/config.txt, or append the following lines:

    dtparam=spi=on
    enable_uart=1
    core_freq=250
    dtoverlay=pi3-disable-bt
    sudo systemctl stop serial-getty@ttyS0.service
    sudo systemctl disable serial-getty@ttyS0.service
    sudo ~/pico_ethernet/test/pi_wire/pi_wire spi

Note: Please adjust the path as needed, depending on where you have installed Pi-Wire. This starts the Pi-Wire software automatically on startup. Sudo is required to run this software, since it sends and receives raw Ethernet packets.

# Connecting Pi-Wire

The SPI interface uses the following pins:

* PMOD pin 1 = CSb = RPi pin 10 (CE0)
* PMOD pin 2 = MOSI = RPi pin 12 (MOSI)
* PMOD pin 3 = MISO = RPi pin 13 (MISO)
* PMOD pin 4 = SCK = RPi pin 14 (SCLK)

The UART interface uses the following pins:

* PMOD pin 1 = CTSb = Ground
* PMOD pin 2 = RxD = RPi pin 15 (Tx)
* PMOD pin 3 = TxD = RPi pin 16 (Rx)
* PMOD pin 4 = RTSb = Unused

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
