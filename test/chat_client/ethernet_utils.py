#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2019 The Aerospace Corporation
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

def mac2str(bytes):
    '''Convert MAC bytes to string (e.g., '8C:DC:D4:48:0D:8B')'''
    return ':'.join('%02X' % b for b in bytes)

def str2mac(str):
    '''Convert MAC string (e.g., '8C:DC:D4:48:0D:8B...') to raw bytes.'''
    return bytes.fromhex(str[:17].replace(':', ''))

def list_eth_interfaces():
    '''
    Returns a list of all Ethernet interfaces and MAC addresses.
    '''
    result = {}
    if os.name =='nt':
        ifs = sca.get_windows_if_list()
        for interface in ifs:
            result[interface['description']] = interface['name']
    else:
        result = sca.get_if_list()
    
    return result

class AsyncEthernetPort:
    '''Ethernet port wrapper. Same interface as serial_utils::AsyncSLIPPort.'''
    def __init__(self, ifobj, logger):
        '''Initialize member variables.'''
        self._iface = ifobj
        #self.lbl = ifobj.data['netid']
        self.lbl = ifobj
        self.mac = str2mac(sca.get_if_hwaddr(ifobj))
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
            self._rx_run = False
            self._rx_thread.join()

    def is_uart(self):
        return False

    def set_callback(self, callback):
        self._callback = callback

    def msg_rcvd(self, packet):
        '''
        Parse and deliver complete packets.

        Convert packet to raw bytes.
        (Expect dst MAC, src MAC, Ethertype, payload = 6+6+2+n).
        '''
        eth_frm = sca.raw(packet)
        if (len(eth_frm) > 14) and (self._callback is not None):
            self._callback(eth_frm)

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
            sca.sendp(sca.Ether(eth_frm), iface=self._iface)
        except:
            self._log.error(self.lbl + ':\n' + traceback.format_exc())

    def _rx_loop(self):
        self._log.info(self.lbl + ': Rx loop start')
        while self._rx_run:
            try:
                sca.sniff(
                    iface=self._iface,  # Use specified interface
                    store=False,        # Don't bother storing for later
                    timeout=0.5,        # Stop every N seconds
                    prn=self.msg_rcvd)  # Callback for each packet
            except:
                self._log.error(self.lbl + ':\n' + traceback.format_exc())
                sleep(1.0)              # Brief delay before retry
        self._log.info(self.lbl + ': Rx loop done')
