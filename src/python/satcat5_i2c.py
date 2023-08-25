#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2023 The Aerospace Corporation
#
# This file is part of SatCat5.
#
# SatCat5 is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# SatCat5 is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.

"""
This file defines functions for various I2C-related SatCat5 peripherals:
    * Conversion of I2C device addresses from various formats.
    * Driver for the ConfigBus-operated I2C controller.
    * Driver for the PCA9548A / TCA9548A I2C multiplexer.
"""

import time

class I2cAddress:
    """
    Conversion functions for I2C device addresses.

    Natively, conventional I2C device addresses are 7-bits followed by
    the read/write flag.  Two bytes are required for 10-bit address mode.

    There are conflicting conventions for representing this in software.
    This wrapper allows unambiguous use of all common conventions:
     * 7-bit addresses (e.g., 0x77 = 1110111) are right-justified.
     * 8-bit addresses (e.g., 0xEE/0xEF = 1110111x) are left-justified
       and come in pairs, treating read and write as a "separate" address.
       (This example refers to the same underlying I2C device address.)
     * 10-bit addresses (e.g., 0x377 = 1101110111) are right-justified.
       See also: https://www.i2c-bus.org/addressing/10-bit-addressing/
       We insert the required 11110 prefix at this time, and shift bits
       9 and 8 to make room for the R/Wb bit.  Doing more work up front
       simplifies downstream processing.
    """

    def addr7(x):
        """ Create I2C address from a 7-bit input (right-justified) """
        return I2cAddress(2 * (x & 0x7F))

    def addr8(x):
        """ Create I2C address from an 8-bit input (left-justified) """
        return I2cAddress(x & 0xFE)

    def addr10(x):
        """ Create I2C address from a 10-bit input (right-justified) """
        ll = x & 0x0300  # Bits 9 downto 8
        rr = x & 0x00FF  # Bits 7 downto 0
        return I2cAddress(0xF000 | (ll << 1) | rr)

    def __init__(self, addr):
        """ Internal use only, please use addr7(), addr8(), or addr10(). """
        self.addr = addr

    def is_10b(self):
        """ Is this address a 10-bit address? """
        return self.addr > 255

class I2cController:
    """
    Driver for a ConfigBus I2C controller (cfgbus_i2c_controller.vhd).
    Accepts a ConfigBus interface (e.g., satcat5_cfgbus.ConfigBus) which
    is typically remotely operated through an Ethernet interface.
    """

    # Define various hardware-related constants:
    REG_IRQ         = 0         # ConfigBus register address
    REG_CFG         = 1         # ConfigBus register address
    REG_STATUS      = 2         # ConfigBus register address
    REG_DATA        = 3         # ConfigBus register address
    CMD_DELAY       = 0x0000    # Control-register opcode
    CMD_START       = 0x0100    # Control-register opcode
    CMD_RESTART     = 0x0200    # Control-register opcode
    CMD_STOP        = 0x0300    # Control-register opcode
    CMD_TXBYTE      = 0x0400    # Control-register opcode
    CMD_RXBYTE      = 0x0500    # Control-register opcode
    CMD_RXFINAL     = 0x0600    # Control-register opcode
    CFG_NOSTRETCH   = 1 << 31   # Configuration flag
    DATA_VALID      = 1 << 8    # Data-register flag
    STATUS_NOACK    = 1 << 3    # Status-register flag
    STATUS_BUSY     = 1 << 2    # Status-register flag
    STATUS_FULL     = 1 << 1    # Status-register flag
    STATUS_RDATA    = 1 << 0    # Status-register flag

    def __init__(self, cfgbus, devaddr):
        """
        Link to the specified ConfigBus register map.

        Keyword arguments:
            cfgbus (ConfigBus):
                Connection to a specific ConfigBus network.
            devaddr (int):
                ConfigBus device address (0-255)
        """
        self._cfg = cfgbus      # ConfigBus object
        self._dev = devaddr     # Device address (0-255)

    def configure(self, refclk_hz, baud_hz=400e3, clock_stretch=True):
        """
        Set interface options such as baud rate and clock-stretching.

        Keyword arguments:
            refclk_hz (int):
                Rate of the reference clock provided to the I2C controller.
            baud_hz (optional int):
                Requested baud rate for I2C communications (default 400 kbps).
            clock_stretch (optional bool):
                Enable I2C clock-stretching (default/True) or ignore
                clock-streching requests from peripherals (False).

        Returns:
            bool: True if operation is succesful.
        """
        div_qtr = (refclk_hz + 4*baud_hz - 1) // (4*baud_hz) - 1
        if clock_stretch: div_qtr |= self.CFG_NOSTRETCH
        return self._cfg.write_reg(self._dev, self.REG_CFG, div_qtr)

    def noack(self):
        """
        Missing acknowledge during most recent transaction?
        (Call this just after returning from read() or write().
        """
        status = self._cfg.read_reg(self._dev, self.REG_STATUS)
        return (status is None) or (status & self.STATUS_NOACK > 0)

    def read(self, devaddr, nread, regaddr=b''):
        """
        Read from the specified I2C device.

        Keyword arguments:
            devaddr (I2cAddress):
                I2C peripheral address.
            nread (int):
                Number of bytes to be read.
            regaddr (optional byte-string):
                I2C register address to send before reading.

        Returns:
            Result as byte-string if successful, otherwise None.
        """
        if isinstance(regaddr, int): regaddr = bytes([regaddr])
        if self._execute(devaddr, regaddr, nread):
            if self.noack(): return None
            return self._read(nread)
        else:
            return None

    def write(self, devaddr, wdata, regaddr=b''):
        """
        Read from the specified I2C device.

        Keyword arguments:
            devaddr (I2cAddress):
                I2C peripheral address.
            wdata (byte-string):
                The data to be sent to the device.
            regaddr (optional byte-string):
                I2C register address to send before writing.

        Returns:
            bool: True if operation is succesful.
        """
        if isinstance(regaddr, int): regaddr = bytes([regaddr])
        return self._execute(devaddr, regaddr + wdata, 0)

    def _execute(self, devaddr, wdata, nread):
        """Formulate and execute an I2C transaction."""
        # Extract raw address bytes (7-bit or 10-bit).
        assert isinstance(devaddr, I2cAddress)
        addr_msb = (devaddr.addr >> 8) & 0xFF
        addr_lsb = (devaddr.addr >> 0) & 0xFF
        # Generate the list of required commands.
        queue = [self.CMD_START]
        if wdata:
            if devaddr.is_10b():
                queue.append(self.CMD_TXBYTE | addr_msb)
                queue.append(self.CMD_TXBYTE | addr_lsb)
            else:
                queue.append(self.CMD_TXBYTE | addr_lsb)
            for wbyte in wdata:
                queue.append(self.CMD_TXBYTE | wbyte)
            if nread > 0:
                queue.append(self.CMD_RESTART)
        if nread > 0:
            if devaddr.is_10b():
                queue.append(self.CMD_TXBYTE | addr_msb | 1)
                queue.append(self.CMD_TXBYTE | addr_lsb)
            else:
                queue.append(self.CMD_TXBYTE | addr_lsb | 1)
            if nread > 1:
                queue.extend([self.CMD_RXBYTE] * (nread-1))
            queue.append(self.CMD_RXFINAL)
        queue.append(self.CMD_STOP)
        # Load commands and wait for completion.
        return self._load(queue) and self._poll()

    def _load(self, ops):
        """Load and execute an array of hardware opcodes."""
        # TODO: Break commands longer than 64 opcodes into smaller chunks?
        return self._cfg.multi_write(self._dev, self.REG_DATA, ops)

    def _poll(self, timeout=1.0):
        """Poll status register until idle."""
        start = time.time()
        while True:
            status = self._cfg.read_reg(self._dev, self.REG_STATUS)
            if status is None: return False
            if not (status & self.STATUS_BUSY): return True
            elapsed = time.time() - start
            if elapsed > timeout: return False

    def _read(self, nread):
        """Read N bytes from the hardware receive queue."""
        rdata = self._cfg.multi_read(self._dev, self.REG_DATA, nread)
        if rdata:
            assert all([r & self.DATA_VALID for r in rdata])
            return bytes([r & 0xFF for r in rdata])
        else:
            return None

class Tca9548:
    """
    Device driver for various pin-compatible I2C switches:
    * NXP Semiconductors PCA9548A
    * Texas Instruments TCA9548A
    """

    def __init__(self, i2c, devaddr):
        """
        Link this object to the specified I2C bus and address.

        Keyword arguments:
            i2c (I2cController):
                ConfigBus I2C controller
            devaddr (I2cAddress):
                I2C peripheral address
        """
        assert isinstance(i2c, I2cController)
        assert isinstance(devaddr, I2cAddress)
        self._i2c = i2c         # I2C
        self._dev = devaddr     # Device address (0-255)

    def select_mask(self, mask):
        """Select one or more channels by bit-mask."""
        return self._i2c.write(self._dev, [mask])

    def select_channel(self, index):
        """Select a single channel by index."""
        return self.select_mask(1 << index)
