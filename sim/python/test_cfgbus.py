# -*- coding: utf-8 -*-

# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

"""
Tests for ConfigBus class in satcat5_cfgbus.py.
Used to check that sent messages are successful and equal to message received.
"""

from cmath import exp
import unittest
import math
import logging, os, sys, time
from struct import pack
logger = logging.getLogger(__name__)

sys.path.append(os.path.join(
    os.path.dirname(__file__), '..', '..', 'src', 'python'))

from satcat5_cfgbus import ConfigBus
from satcat5_eth import AsyncEthernetPort

ETYPE_COMMAND   = 0x1234
ETYPE_REPLY     = ETYPE_COMMAND + 1
HOST_MACADDR    = b'\x01\x23\x45\x67\x89\xAB'

OPCODE_WR_RPT   = 0x2F
OPCODE_WR_INC   = 0x3F
OPCODE_RD_RPT   = 0x40
OPCODE_RD_INC   = 0x50

class ServerStub:
    """Minimal stub that mimics AsyncEthernetPort and implements a ConfigBus server."""
    def __init__(self, macaddr):
        self.callback   = None
        self.mac        = macaddr
        self.wrval      = None      # Value(s) from most recent Write
        self.rdval      = None      # Reply value(s) for next Read

    def set_callback(self, callback):
        self.callback = callback

    def msg_send(self, eth_frm, blocking=False):
        """Handle command messages from the ConfigBus class."""
        # Is this a command packet?
        dst_mac = eth_frm[0:6]
        src_mac = eth_frm[6:12]
        etype   = int.from_bytes(eth_frm[12:14], 'big')
        if dst_mac != self.mac: return          # Wrong recipient?
        if etype != ETYPE_COMMAND: return       # Wrong EtherType?
        # Parse the command header.
        opcode = eth_frm[14]
        nwords = eth_frm[15] + 1
        adr = int.from_bytes(eth_frm[18:22], 'big')
        devaddr = adr // 1024
        regaddr = adr - 1024*devaddr
        # Send the appropriate reply.
        if opcode == OPCODE_WR_INC or opcode == OPCODE_WR_RPT:
            self.wrval = []
            for i in range(nwords):
                self.wrval.append(int.from_bytes(eth_frm[22+i*4 : 26+i*4], 'big'))
            self.send_response(src_mac, opcode, nwords, devaddr, regaddr, None)
        elif opcode == OPCODE_RD_INC or opcode == OPCODE_RD_RPT:
            self.send_response(src_mac, opcode, nwords, devaddr, regaddr, self.rdval)

    def send_response(self, reply_mac, opcode, nwords, devaddr, regaddr, read_vals):
        """Formulate and send a response to the callback object."""
        if self.callback is None: return
        rsvd = 0
        addr = 1024 * devaddr + regaddr
        err = 0
        eth_hdr = reply_mac + self.mac + pack('>H', ETYPE_REPLY)
        if read_vals is None:
            eth_dat = pack(f'>BBHLB', opcode, nwords-1, rsvd, addr, err)
        else:
            eth_dat =  pack(f'>BBHL{nwords}LB', opcode, nwords-1, rsvd, addr, *read_vals, err)
        self.callback(eth_hdr + eth_dat)

class ConfigBusTests(unittest.TestCase):
    # Called once to set up variables for testing
    @classmethod
    def setUpClass(cls):
        cls.server = ServerStub(HOST_MACADDR)
        cls.uut = ConfigBus(cls.server, HOST_MACADDR, ethertype=ETYPE_COMMAND)

    def test_write_1(self):
        expected_val = 1
        devaddr = 0
        regaddr = 0
        success = self.uut.write_reg(devaddr, regaddr, expected_val)
        with self.subTest():
            self.assertTrue(success)
        with self.subTest():
            self.assertEqual(self.server.wrval, [expected_val])

    def test_write_2(self):
        expected_val = 2**16
        nwords = 1
        devaddr = 128
        regaddr = 512
        success = self.uut.write_reg(devaddr, regaddr, expected_val)
        with self.subTest():
            self.assertTrue(success)
        with self.subTest():
            self.assertEqual(self.server.wrval, [expected_val])

    def test_multi_write_1(self):
        expected_val = [1,2,3,4]
        devaddr = 1
        regaddr = 1
        success = self.uut.multi_write(devaddr, regaddr, expected_val)
        with self.subTest():
            self.assertTrue(success)
        with self.subTest():
            self.assertEqual(self.server.wrval, expected_val)

    def test_multi_write_2(self):
        expected_val = [0,1,256,2**31,5,6,7,8]
        nwords = len(expected_val)
        devaddr = 1
        regaddr = 1
        success = self.uut.multi_write(devaddr, regaddr, expected_val)
        with self.subTest():
            self.assertTrue(success)
        with self.subTest():
            self.assertEqual(self.server.wrval, expected_val)

    def test_read_1(self):
        expected_val = 1
        nwords = 1
        devaddr = 0
        regaddr = 0
        self.server.rdval = [expected_val]
        actual_val = self.uut.read_reg(devaddr, regaddr)
        with self.subTest():
            self.assertEqual(actual_val, expected_val)

    def test_read_2(self):
        expected_val = 2**16
        self.read_val = expected_val
        nwords = 1
        devaddr = 250
        regaddr = 1000
        self.server.rdval = [expected_val]
        actual_val = self.uut.read_reg(devaddr, regaddr)
        with self.subTest():
            self.assertEqual(actual_val, expected_val)

    def test_multi_read_1(self):
        expected_val = [1,2,3,4]
        devaddr = 1
        regaddr = 1
        self.server.rdval = expected_val
        actual_val = self.uut.multi_read(devaddr, regaddr, len(expected_val))
        with self.subTest():
            self.assertEqual(actual_val, expected_val)

    def test_multi_read_2(self):
        expected_val = [9999,0,6,2**31,9,10,11,12]
        devaddr = 1
        regaddr = 1
        self.server.rdval = expected_val
        actual_val = self.uut.multi_read(devaddr, regaddr, len(expected_val))
        with self.subTest():
            self.assertEqual(actual_val, expected_val)

if __name__ == '__main__':
    unittest.main()

