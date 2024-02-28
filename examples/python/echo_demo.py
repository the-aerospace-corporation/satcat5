# -*- coding: utf-8 -*-

# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

"""
Demonstration app for using the SatCat5 "AsyncEthernetPort" object.
Sets up an "echo" service that will loopback messages forever.
It can be used to measure the turnaround time inherent in the ScaPy API.
"""

# System imports.
import logging, os, sys, time
logger = logging.getLogger(__name__)

# Additional imports from SatCat5 core.
sys.path.append(os.path.join(
    os.path.dirname(__file__), '..', '..', 'src', 'python'))
import satcat5_eth

"""A simple class that echoes anything with the designated EtherType."""
class Echo:
    def __init__(self, iface_name, etype_rx=0x1234, etype_tx=0x1234):
        """Open the designated network interface."""
        # Open the designated interface and set up receive callback.
        self.iface = satcat5_eth.AsyncEthernetPort(iface_name, iface_name, logger)
        self.iface.set_callback(self.rcvd)
        # Other initialization.
        self.etype_rx = etype_rx.to_bytes(2, byteorder='big')
        self.etype_tx = etype_tx.to_bytes(2, byteorder='big')
        self.ref_time = time.time()
        self.echo_frm = self.iface.mac + self.iface.mac + self.etype_tx

    def rcvd(self, ethbytes):
        """AsyncEthernetPort calls this method for each received frame."""
        if ethbytes[12:14] == self.etype_rx:
            elapsed = time.time() - self.ref_time
            print('Elapsed time: %.3f' % elapsed)
            time.sleep(0.1)     # Controlled delay for rate limiting
            self.send(ethbytes) # Keep re-sending the same message

    def send(self, ethbytes):
        """Send an Ethernet frame using AsyncEthernetPort."""
        self.ref_time = time.time()
        self.iface.msg_send(ethbytes)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: python echo_demo.py [Ethernet interface name]')
        print('  Typical network names vary by platform.  On Linux, "/dev/eth0".')
        print('  On Windows, "Intel(R) Ethernet Connection (2) I219-LM".')
        exit(-1)
    print('Opening network interface...')
    echo = Echo(sys.argv[1])    # Start the echo service.
    print('Running. Hit Ctrl+C to stop.')
    echo.send(echo.echo_frm)    # Kick off the infinite loop
    while True: time.sleep(1)   # Keep running until user hits Ctrl+C
