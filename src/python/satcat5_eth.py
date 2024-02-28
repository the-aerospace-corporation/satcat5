#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

"""
Define interface for sending and receiving raw-Ethernet-frames,
which is functionally equivalent to satcat5_uart::AsyncSLIPPort.
"""

from scapy import all as sca
import scapy
import threading
import traceback
from time import sleep
import os

# Use libpcap super sockets (non-native)
sca.conf.use_pcap = True

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
        Values are ID-strings suitable for passing to ScaPy.
        (Formatting of the ID-strings is OS-specific)
    """
    result = {}
    if os.name =='nt':
        # Different versions of the Scapy API move the get_windows_if_list() function.
        # Supporting older versions by using trial-and-error to find it.
        try:
            ifs = sca.get_windows_if_list()
        except AttributeError:
            try:
                ifs = scapy.arch.windows.get_windows_if_list()
            except Exception:
                raise

        for interface in ifs:
            result[interface['description']] = interface['name']
    else:
        ifs = sca.get_if_list()
        for interface in ifs:
            result[interface] = interface
    return result

class AsyncEthernetPort:
    """Ethernet port wrapper. Same interface as serial_utils::AsyncSLIPPort."""
    def __init__(self, label, iface, logger, promisc=True):
        """
        Initialize member variables.

        Args:
            label (str):
                Human-readable label for this interface.
            iface (str):
                ScaPy interface-ID string.  (See list_eth_interfaces.)
            logger (Logger):
                Logger object (logging.Logger) for reporting errors.
            promisc (bool):
                Enable promiscuous mode? (Default True)
                May require admin/root privileges.
        """
        self._iface = sca.conf.L2socket(iface, promisc=promisc)
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
        """Stop the ScaPy sniffer."""
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
                (i.e., If using ScaPy packet objects, call "pkt.raw()".)
                Should contain Dst + Src + Type + Payload
            blocking (bool):
                Wait to finish before returning? (Default false)
        """
        try:
            if len(eth_frm) < 60:
                len_pad = 60 - len(eth_frm)
                eth_frm += len_pad * b'\x00'
            self._iface.send(eth_frm)
            if blocking: sleep(0.001)
        except:
            self._log.error(self.lbl + ':\n' + traceback.format_exc())

    def _rx_loop(self):
        """Main loop for the receive thread."""
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
