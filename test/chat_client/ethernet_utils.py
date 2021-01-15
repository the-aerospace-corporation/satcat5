#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2019, 2020 The Aerospace Corporation
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

'''
Define interface for sending and receiving raw-Ethernet-frames,
which is functionally equivalent to serial_utils::AsyncSLIPPort.
'''

from scapy import all as sca
import threading
import traceback
from time import sleep
import os

# Use libpcap super sockets (non-native)
sca.conf.use_pcap = True

def mac2str(bytes):
    '''Convert MAC bytes to string (e.g., '8C:DC:D4:48:0D:8B')'''
    return ':'.join('%02X' % b for b in bytes)

def str2mac(str):
    '''Convert MAC string (e.g., '8C:DC:D4:48:0D:8B...') to raw bytes.'''
    return bytes.fromhex(str[:17].replace(':', ''))

def list_eth_interfaces():
    '''
    Returns a dictionary of all Ethernet interfaces and MAC addresses.
    Keys are human-readable labels, values are ScaPy interface-ID strings.
    The formatting of ID strings is platform-specific.
    '''
    result = {}
    if os.name =='nt':
        ifs = sca.get_windows_if_list()
        for interface in ifs:
            result[interface['description']] = interface['name']
    else:
        ifs = sca.get_if_list()
        for interface in ifs:
            result[interface] = interface
    return result

class AsyncEthernetPort:
    '''Ethernet port wrapper. Same interface as serial_utils::AsyncSLIPPort.'''
    def __init__(self, label, iface, logger):
        '''
        Initialize member variables.
        Keyword arguments:
        label -- Human-readable label for this interface.
        iface -- ScaPy interface-ID string.  (See list_eth_interfaces.)
        logger -- Logger object for reporting status and errors.
        '''
        self._iface = sca.conf.L2socket(iface, promisc=True)
        self.lbl = label
        self.mac = str2mac(sca.get_if_hwaddr(iface))
        self._callback = None
        self._log = logger
        self._rx_run = True
        # Reduce ScaPy verbosity (default is rather high).
        sca.conf.verb = 0
        # Create and start the worker thread.
        self._rx_thread = threading.Thread(
            target=self._rx_loop,
            name='Ethernet receive')
        self._rx_thread.setDaemon(True)
        self._rx_thread.start()

    def close(self):
        '''Stop the ScaPy sniffer.'''
        if self._rx_run:
            # Ask work thread to stop and close the socket.
            # (This sometimes helps break out of ongoing recv() calls.)
            self._rx_run = False
            self._iface.close()
            # Attempt to close down gracefully, but don't wait forever.
            self._rx_thread.join(0.5)

    def is_uart(self):
        '''Is this interface a UART or a true Ethernet port?'''
        return False

    def set_callback(self, callback):
        '''Set callback function for received frames.'''
        self._callback = callback

    def msg_send(self, eth_frm):
        '''
        Send frame with Dst, Src, Type, Payload (no checksum).

        Create and send ScaPy frame.  (Tool adds checksum.)
        Zero-pad runt data so frame + CRC is at least 64 bytes
        '''
        try:
            if len(eth_frm) < 60:
                len_pad = 60 - len(eth_frm)
                eth_frm += len_pad * b'\x00'
            self._iface.send(eth_frm)
        except:
            self._log.error(self.lbl + ':\n' + traceback.format_exc())

    def _rx_loop(self):
        '''Main loop for the receive thread.'''
        self._log.info(self.lbl + ': Rx loop start')
        while self._rx_run:
            try:
                pkt = self._iface.nonblock_recv()
                if pkt is None:
                    sleep(0.01) # Short sleep so we don't hog CPU
                elif self._callback is not None:
                    self._callback(sca.raw(pkt))
            except:
                self._log.error(self.lbl + ':\n' + traceback.format_exc())
                sleep(1.0)              # Brief delay before retry
        self._log.info(self.lbl + ': Rx loop done')
