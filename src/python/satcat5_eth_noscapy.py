#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2022 The Aerospace Corporation
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
Define interface for sending and receiving raw-Ethernet-frames,
which is functionally equivalent to satcat5_uart::AsyncSLIPPort.
"""

import socket
import fcntl
import struct
import threading
import traceback
import time

def mac2str(bytes):
    """
    Convert MAC byte-string to human-readable string
    e.g., b'\x8C\xDC\xD4\x48\x0D\x8B' --> '8C:DC:D4:48:0D:8B'

    Args:
        bytes (bstr): MAC as byte-string.
    Returns:
        str: Human-readable colon-delimited string.
    """
    return ':'.join('%02X' % b for b in bytes)

def str2mac(str):
    """
    Convert human-readable MAC string to a byte-string.
    e.g., '8C:DC:D4:48:0D:8B' --> b'\x8C\xDC\xD4\x48\x0D\x8B'

    Args:
        bytes (str): Human-readable colon-delimited string.
    Returns:
        bstr: MAC as byte-string.
    """
    return bytes.fromhex(str[:17].replace(':', ''))

def list_eth_interfaces():
    """
    Construct a list of all available Ethernet interfaces.

    Returns:
        A dictionary of Ethernet interfaces.
        Keys are human-readable names.
        Values are ID-strings suitable for passing to getHwAddr.
        (Formatting of the ID-strings is OS-specific)
    """
    result = {}    
    ifs = socket.if_nameindex() # Windows: Python 3.8, Linux: Python 3.3
    for _, interface in ifs:
        result[interface] = interface # Returns a tuple
    return result


def getHwAddr(ifname):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    info = fcntl.ioctl(s.fileno(), 0x8927,  struct.pack('256s', bytes(ifname, 'utf-8')[:15]))
    return ':'.join('%02x' % b for b in info[18:24])

class AsyncEthernetPort:
    """Ethernet port wrapper. Same interface as serial_utils::AsyncSLIPPort."""
    def __init__(self, label, iface, logger, promisc=True):
        """
        Initialize member variables.

        Args:
            label (str):
                Human-readable label for this interface.
            iface (str):
                Interface name.  (See list_eth_interfaces.)
            logger (Logger):
                Logger object (logging.Logger) for reporting errors.
            promisc (bool):
                Enable promiscuous mode? (Default True)
                May require admin/root privileges.
        """
        ETH_P_ALL = 0x0003
        self._iface = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, 
                                    socket.htons(ETH_P_ALL))
        self._iface.bind((iface, ETH_P_ALL))
        self._iface.setblocking(False)
        self._iface.settimeout(0.01) # TODO: configurable?
        self.lbl = label
        self.mac = str2mac(getHwAddr(iface))
        self._callback = None
        self._log = logger
        self._rx_run = True
        # Create and start the worker thread.
        self._rx_thread = threading.Thread(
            target=self._rx_loop,
            name='Ethernet receive')
        self._rx_thread.setDaemon(True)
        self._rx_thread.start()

    def close(self):
        """Stop the rx thread."""
        if self._rx_run:
            # Ask work thread to stop and close the socket.
            # (This sometimes helps break out of ongoing recv() calls.)
            self._rx_run = False
            self._iface.close()
            # Attempt to close down gracefully, but don't wait forever.
            self._rx_thread.join(0.5)

    def is_uart(self):
        """Is this interface a UART or a true Ethernet port?"""
        return False

    def set_callback(self, callback):
        """
        Set "callback" function that is called for each received frame.
        The function should accept a single byte-string argument, which
        contains the raw-Ethernet header and contents but not the FCS.

        Args:
            callback (function): The new callback function.
        """
        self._callback = callback

    def msg_send(self, eth_frm, blocking=False):
        """
        Send an Ethernet frame.
        Frames shorter than the minimum size will be zero-padded.

        Args:
            eth_frm (bstr):
                Byte string containing entire frame except FCS.
                Should contain Dst + Src + Type + Payload
            blocking (bool):
                Wait to finish before returning? (Default false)
        """
        try:
            if len(eth_frm) < 60:
                len_pad = 60 - len(eth_frm)
                eth_frm += len_pad * b'\x00'
            self._iface.send(eth_frm)
            if blocking: time.sleep(0.001)
        except:
            self._log.error(self.lbl + ':\n' + traceback.format_exc())

    def _rx_loop(self):
        """Main loop for the receive thread."""
        self._log.info(self.lbl + ': Rx loop start')
        while self._rx_run:
            try:
                try:
                    pkt = self._iface.recv(8192)
                    if self._callback is not None:
                        self._callback(pkt)
                except socket.timeout:
                    pass
            except:
                self._log.error(self.lbl + ':\n' + traceback.format_exc())
                time.sleep(1.0)              # Brief delay before retry
        self._log.info(self.lbl + ': Rx loop done')
