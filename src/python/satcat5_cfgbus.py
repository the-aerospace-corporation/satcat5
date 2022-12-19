# -*- coding: utf-8 -*-

# Copyright 2021, 2022 The Aerospace Corporation
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
Helper tool for writing to a ConfigBus host using a raw-Ethernet or UART port.
Includes simple calls for other common peripherals, such as GPO and MDIO.
See also: cfgbus_host_uart.vhd, cfgbus_peripherals.vhd
"""

from struct import pack, unpack
from threading import Condition
from time import sleep
import threading

class ConfigBus:
    # Define command opcodes.
    OPCODE_WR_RPT   = 0x2F
    OPCODE_WR_INC   = 0x3F
    OPCODE_RD_RPT   = 0x40
    OPCODE_RD_INC   = 0x50

    lock = threading.Lock()

    """Ethernet interface controller linked to a specific ConfigBus."""
    def __init__(self, if_obj, mac_addr, ethertype=0x5C01, fastwrite=False, readable=True):
        """
        Create object connected to a specific ConfigBus interface.

        Args:
            if_obj (Object):
                Interface object defining .mac, .msg_send(), .set_callback().
                (e.g., AsyncSLIPPort, AsyncEthernetPort, etc.)
            mac_addr (bstr):
                MAC address of the remote ConfigBus host.
            ethertype (int):
                EtherType for this ConfigBus host (default 0x5C01).
                Replies have EtherType N+1 (i.e., default 0x5C02).
                Must be in range 0x0600 to 0xFFFF.
            fastwrite (bool):
                Should writes wait for a response (default)? Or use fast mode?
                Fast mode requires the ConfigBus host to implement sequence
                counter echo mode (new in v2.2) to distinguish replies.
            readable (bool):
                Is this interface readable? (Default) Or write-only?
                Write-only ports can still send read commands, which often
                have side effects, but aren't able to receive the reply.
        """
        # Store basic parameters for later.
        self.cv     = Condition()   # For thread-sync
        self.ifobj  = if_obj
        self.fastwr = fastwrite or not readable
        self.read   = readable
        self.reply  = None          # Received reply
        self.seq    = 0             # Sequence counter
        # Fixed Ethernet header: Destination, Source, EtherType
        self.etype_cmd = pack('>H', ethertype)
        self.etype_ack = pack('>H', ethertype + 1)
        self.ethhdr = mac_addr + if_obj.mac + self.etype_cmd
        # Register callback if this is a readable interface.
        if readable:
            self.ifobj.set_callback(self._msg_rcvd)

    def _msg_send(self, cmd):
        """Internal helper function for sending commands."""
        self.reply = None
        self.ifobj.msg_send(self.ethhdr + cmd, blocking=True)


    def _msg_rcvd(self, frm):
        """Internal callback for received replies."""
        # Ignore anything that doesn't have the right EtherType.
        if ((len(frm) < 20) or
            (frm[12] != self.etype_ack[0]) or
            (frm[13] != self.etype_ack[1])): 
            return
        # In fast-write mode, also filter by sequence count.
        # Store valid replies and wake up any waiting threads.
        with self.cv:
            if self.fastwr and self.seq != frm[16]: return
            self.reply = frm[14:]
            self.cv.notify()

    def _msg_skip(self):
        """Internal function called to skip the next reply."""
        with self.cv: self.seq = (self.seq + 1) % 256

    def _msg_wait(self, timeout):
        """Internal function that waits for reply from ConfigBus host."""
        with self.cv:
            if self.reply is None:
                self.cv.wait(timeout)
            tmp = self.reply
            self.reply = None
            self.seq = (self.seq + 1) % 256
        return tmp

    def write_reg(self, devaddr, regaddr, val, timeout=0.1):
        """
        Send a ConfigBus register-write command.

        Args:
            devaddr (int):
                ConfigBus device-address (0-255)
            regaddr (int):
                ConfigBus register-address (0-1023)
            val (int):
                Value to be written (should fit in uint32_t)
            timeout (float):
                Timeout for reply, in seconds. (Default = 0.1)

        Returns:
            bool: True if operation is succesful.
        """
        # Construct and send the command.
        with self.lock:
            cmd = self.OPCODE_WR_RPT            # Write command (no-increment)
            flg = 0                             # Single-word write (flg = number of words - 1)
            adr = 1024 * devaddr + regaddr      # Combined address
            frm = pack('>BBBBLL', cmd, flg, self.seq, 0, adr, val)
            self._msg_send(frm)
            # Wait for reply unless in "fast-write" mode.
            if self.fastwr:
                self._msg_skip()                # Ignore reply
                return True                     # Assume success
            else:
                reply = self._msg_wait(timeout) # Wait for reply or timeout
                return reply is not None        # Success?

    def multi_write(self, devaddr, regaddr, vals, timeout=0.1, increment=False):
        """
        Send a ConfigBus register-write command containing multiple words.

        Args:
            devaddr (int):
                ConfigBus device-address (0-255)
            regaddr (int):
                ConfigBus register-address (0-1023)
            vals (list of int):
                Values to be written (Each value fits in uint32_t)
                Array size should be in range 2 to 8
                For single writes use write_reg()
            timeout (float):
                Timeout for reply, in seconds. (Default = 0.1)
            increment (bool):
                Register auto-increment. (Default = False)

        Returns:
            bool: True if operation is succesful.
        """
        with self.lock:
            cmd = self.OPCODE_WR_INC if increment else self.OPCODE_WR_RPT
            flg = len(vals) - 1                 # Number of words - 1
            adr = 1024 * devaddr + regaddr      # Combined address
            frm = pack(f'>BBBBL{len(vals)}L', cmd, flg, self.seq, 0, adr, *vals)
            self._msg_send(frm)
            # Wait for reply?
            if self.fastwr:
                self._msg_skip()                # Ignore reply
                return True                     # Assume success
            else:
                reply = self._msg_wait(timeout) # Wait for reply or timeout
                return reply is not None        # Success?

    def read_reg(self, devaddr, regaddr, timeout=0.1):
        """
        Send a ConfigBus register-read command.

        Args:
            devaddr (int):
                ConfigBus device-address (0-255)
            regaddr (int):
                ConfigBus register-address (0-1023)
            timeout (float):
                Timeout for reply, in seconds. (Default = 0.1)

        Returns:
            int: Read register value if successful, None otherwise.
        """
        with self.lock:
            # Construct and send the command.
            cmd = self.OPCODE_RD_RPT            # Read command (no-increment)
            flg = 0                             # Single-word read (flg = number of words - 1)
            adr = 1024 * devaddr + regaddr      # Combined address
            frm = pack('>BBBBL', cmd, flg, self.seq, 0, adr)
            self._msg_send(frm)
            # If this is a readable port, wait for reply.
            if self.read:
                reply = self._msg_wait(timeout) # Wait for reply or timeout
                if reply is None or len(reply) < 13: 
                    return None                 # Timeout
                (word, status) = unpack('>LB', reply[8:13])
                if status: return None          # Missing-ACK
                else: return word               # Success
            else:
                self._msg_skip()                # Ignore reply
                return None                     # Not readable

    def multi_read(self, devaddr, regaddr, nwords, timeout=0.1, increment=False):
        """
        Send a ConfigBus multiple word register-read command.

        Args:
            devaddr (int):
                ConfigBus device-address (0-255)
            regaddr (int):
                ConfigBus register-address (0-1023)
            nwords (int):
                Number of words to read (2-8)
            timeout (float):
                Timeout for reply, in seconds. (Default = 0.1)
            increment (bool):
                Register auto-increment. (Default = False)

        Returns:
            int: Read register value if successful, None otherwise.
        """
        with self.lock:
            # Construct and send the command.
            cmd = self.OPCODE_RD_INC if increment else self.OPCODE_RD_RPT
            flg = nwords - 1
            adr = 1024 * devaddr + regaddr      # Combined address
            frm = pack('>BBBBL', cmd, flg, self.seq, 0, adr)
            self._msg_send(frm)
            # If this is a readable port, wait for reply.
            if self.read:
                reply = self._msg_wait(timeout) # Wait for reply or timeout
                if reply is None or len(reply) < 13:
                    return None                 # Timeout
                words = list(unpack(f'>{nwords}L', reply[8:12 + 4*flg]))
                status = reply[12 + 4*flg]
                if status: return None          # Missing-ACK
                else: return words              # Success
            else:
                self._msg_skip()                # Ignore reply
                return None                     # Not readable

class ConfigGPO:
    """
    Controller for a discrete 32-bit General Purpose Output (GPO) register.
    Each register bit is directly tied to an FPGA pin or a control flag.
    """

    def __init__(self, cfgbus, devaddr, regaddr, init=0):
        """
        Create a ConfigGPO object linked to the specified ConfigBus register.

        Args:
            cfgbus (ConfigBus):
                ConfigBus object linked to a remote ConfigBus interface.
            devaddr (int):
                ConfigBus device-address (0-255)
            regaddr (int):
                ConfigBus register-address (0-1023)
            init (int):
                Initial GPO state (default 0)

        """
        self._cfg = cfgbus      # ConfigBus object
        self._dev = devaddr     # Device address (0-255)
        self._reg = regaddr     # Register address (0-1023)
        self._gpo = init        # Initial GPO state

    def read(self):
        """
        Read the current state of the GPO register.

        Returns:
            int: Current GPO state as a bit-mask.
        """
        return self._cfg.read_reg(self._dev, self._reg)

    def clr_mask(self, mask):
        """
        Lower/clear specific bits in the GPO register.

        Args:
            mask (int): Mask indicating bits to be cleared.
        """
        self.set(self._gpo & ~mask)

    def set_mask(self, mask):
        """
        Raise/set specific bits in the GPO register.

        Args:
            mask (int): Mask indicating bits to be cleared.
        """
        self.set(self._gpo | mask)

    def set(self, bits):
        """
        Directly set new GPO register value.

        Args:
            bits (int): Mask indicating the new state for all GPO bits.
        """
        self._gpo = bits
        self._cfg.write_reg(self._dev, self._reg, bits)

class ConfigMDIO:
    """
    Controller for a specific MDIO interface, which is usually used to
    configure attached Ethernet PHY ASIC(s).  Includes support for
    indirect registers (Debug, MMD3, MMD7, etc.)
    """
    # TODO: Add support for reads.
    CMD_WRITE       = (0x01 << 26)  # Read = 0b01
    CMD_READ        = (0x02 << 26)  # Read = 0b10
    STATUS_FULL     = (1 << 31)     # Command FIFO is full
    STATUS_VALID    = (1 << 30)     # Reply contains data
    STATUS_MASK     = 0xFFFF        # Mask for reply data

    def __init__(self, cfgbus, devaddr, regaddr):
        """
        Link to the specified ConfigBus register.

        Args:
            cfgbus (ConfigBus):
                Connection to a specific ConfigBus network.
            devaddr (int):
                ConfigBus device address for this MDIO port (0-255)
            regaddr (int):
                ConfigBus register address for this MDIO port (0-1023)
        """
        self._cfg = cfgbus      # ConfigBus object
        self._dev = devaddr     # Device address (0-255)
        self._reg = regaddr     # Register address (0-1023)

    def mdio_read(self, phy_addr, reg_addr):
        # TODO: Add support for indirect reads.
        """
        Read from the specified MDIO register.

        Keyword arguments:
            phy_addr (int):
                MDIO physical address for the remote device.
            reg_addr (int):
                MDIO register address in the Direct page.

        Returns:
            int: 16-bit MDIO register value if successful, None otherwise.
        """
        # Send the read command to the MDIO controller.
        # See "mdio_send" for more information on command format.
        cmd = self.CMD_READ | (phy_addr << 21) | (reg_addr << 16)
        self._cfg.write_reg(self._dev, self._reg, cmd)
        sleep(0.001)   # Brief delay for command execution
        # Read and parse the result.
        result = self._cfg.read_reg(self._dev, self._reg)
        if result is None:
            return None                     # Read timeout
        elif result & STATUS_VALID:
            return result & STATUS_MASK     # Success
        else:
            return None                     # MDIO error

    def mdio_send(self, phy_addr, reg_addr, reg_data):
        """
        Send basic MDIO command to specified port and address.

        Args:
            phy_addr (int):
                MDIO physical address for the remote device.
            reg_addr (int):
                MDIO register address in the Direct page.
            reg_data (int):
                MDIO register data to be written.
        """
        # Send the write command to the MDIO controller (see cfgbus_mdio.vhd):
        #   * Bits 31-28: Reserved / zeros
        #   * Bits 27-26: Operator ("01" = write, "10" = read)
        #   * Bits 25-21: PHY address
        #   * Bits 20-16: REG address
        #   * Bits 15-00: Write-data (Ignored by reads)
        cmd = self.CMD_WRITE | (phy_addr << 21) | (reg_addr << 16) | reg_data
        self._cfg.write_reg(self._dev, self._reg, cmd)
        sleep(0.001)   # Brief delay for command execution

    def mdbg_send(self, phy_addr, reg_addr, reg_data):
        """
        Indirect write to AR8031 debug register.

        Args:
            phy_addr (int):
                MDIO physical address for the remote device.
            reg_addr (int):
                MDIO register address in the Debug page.
            reg_data (int):
                MDIO register data to be written.
        """
        self.mdio_send(phy_addr, 29, reg_addr)  # Debug register address
        self.mdio_send(phy_addr, 30, reg_data)  # Debug register value

    def mmd3_send(self, phy_addr, reg_addr, reg_data):
        """
        Indirect write to MMD3 register page.

        Args:
            phy_addr (int):
                MDIO physical address for the remote device.
            reg_addr (int):
                MDIO register address in the MMD3 page.
            reg_data (int):
                MDIO register data to be written.
        """
        self.mdio_send(phy_addr, 13, 0x0003)    # Next command = MMD3 address
        self.mdio_send(phy_addr, 14, reg_addr)  # Register address
        self.mdio_send(phy_addr, 13, 0x4003)    # Next command = MMD3 data
        self.mdio_send(phy_addr, 14, reg_data)  # Register value

    def mmd7_send(self, phy_addr, reg_addr, reg_data):
        """
        Indirect write to MMD7 register page.

        Args:
            phy_addr (int):
                MDIO physical address for the remote device.
            reg_addr (int):
                MDIO register address in the MMD7 page.
            reg_data (int):
                MDIO register data to be written.
        """
        self.mdio_send(phy_addr, 13, 0x0007)    # Next command = MMD7 address
        self.mdio_send(phy_addr, 14, reg_addr)  # Register address
        self.mdio_send(phy_addr, 13, 0x4007)    # Next command = MMD7 data
        self.mdio_send(phy_addr, 14, reg_data)  # Register value
