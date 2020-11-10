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
Define asynchronous, frame-based serial port interfaces and SLIP conversion
functions.  Messages are assumed to use fixed delimiter characters.
'''

from random import randrange
from struct import pack, unpack
from time import sleep
from zlib import crc32
import serial
import serial.tools.list_ports as lp
import threading
import traceback

# Define various Serial Line Internet Protocol (SLIP) constants.
# See also: https://en.wikipedia.org/wiki/Serial_Line_Internet_Protocol
SLIP_END        = b'\xC0'
SLIP_ESC        = b'\xDB'
SLIP_ESC_END    = b'\xDB\xDC'
SLIP_ESC_ESC    = b'\xDB\xDD'

def list_uart_interfaces():
    '''Return a list of all UART interface names.'''
    result = {}
    for dev in lp.comports():
        os_name = dev.device
        label = os_name + ': ' + dev.description
        result[label] = os_name
    return result

def ethernet_crc(pkt):
    '''Given byte-string, calculate Ethernet-FCS (CRC32)'''
    crc_int = crc32(pkt) & 0xFFFFFFFF
    return pack('<L', crc_int)

def crc_self_test():
    '''Self-test function to verify CRC parameters.'''
    # Define each reference packet:
    # https://www.cl.cam.ac.uk/research/srg/han/ACS-P35/ethercrc/
    PKT1 = b"\xFF\xFF\xFF\xFF\xFF\xFF\x00\x20\xAF\xB7\x80\xB8\x08\x06\x00" \
         + b"\x01\x08\x00\x06\x04\x00\x01\x00\x20\xAF\xB7\x80\xB8\x80\xE8" \
         + b"\x0F\x94\x00\x00\x00\x00\x00\x00\x80\xE8\x0F\xDE\xDE\xDE\xDE" \
         + b"\xDE\xDE\xDE\xDE\xDE\xDE\xDE\xDE\xDE\xDE\xDE\xDE\xDE\xDE\xDE"
    REF1 = b"\x9E\xD2\xC2\xAF"

    # https://electronics.stackexchange.com/questions/170612/fcs-verification-of-ethernet-frame
    PKT2 = b"\xFF\xFF\xFF\xFF\xFF\xFF\x00\x00\x00\x04\x14\x13\x08\x00\x45" \
         + b"\x00\x00\x2E\x00\x00\x00\x00\x40\x11\x7A\xC0\x00\x00\x00\x00" \
         + b"\xFF\xFF\xFF\xFF\x00\x00\x50\xDA\x00\x12\x00\x00\x42\x42\x42" \
         + b"\x42\x42\x42\x42\x42\x42\x42\x42\x42\x42\x42\x42\x42\x42\x42"
    REF2 = b"\x9B\xF6\xD0\xFD"

    # Check each reference against the ethernet_crc() function:
    errcount = 0
    if REF1 != ethernet_crc(PKT1):
        print("CRC Mismatch #1")
        errcount += 1
    if REF2 != ethernet_crc(PKT2):
        print("CRC Mismatch #2")
        errcount += 1
    return errcount

class AsyncSerialPort:
    '''Frame-based UART class with adjustable delimiter.'''
    def __init__(self, logger, callback, msg_delim=b'\n'):
        '''
        Initialize member variables.
        Keyword arguments:
        logger -- A Logger object, i.e., logging.getLogger(xx)
        callback -- Function to be called for each received frame (or None).
        msg_delim -- Character that marks inter-frame boundaries, default '\n'
        '''
        self._baudrate = 0
        self._callback = callback
        self._delim = msg_delim
        self._lbl = 'Placeholder'
        self._log = logger
        self._run = False
        self._tx_lock = threading.Lock()
        self._tx_buff = b''
        # Create placeholder Serial object and worker threads.
        self._port = serial.Serial()
        self._rx_thread = None
        self._tx_thread = None

    def open(self, portname, baudrate=921600):
        '''
        Open the specified UART port.
        Keyword arguments:
        portname -- Name of the UART interface, suitable for Serial constructor.
        baudrate -- Baud rate of the UART port, in bits per second. (Default 921,600)
        '''
        self._lbl = portname
        try:
            # Cleanup if already open.
            self.close()
            # Open the specified port.
            self._log.info(self._lbl + ': Opening')
            self._port = serial.Serial(
                port = portname,
                baudrate = baudrate,
                timeout = 1)
            # Set RTS to idle state (ready).
            # Note inverted convention: True = 0V, False = 3.3V.
            self._port.rtscts = False
            self._port.rts = True
            # Start thread for receiving data.
            self._run = True
            self._rx_thread = threading.Thread(
                target=self._rx_loop,
                name='UART receive')
            self._rx_thread.setDaemon(True)
            self._rx_thread.start()
            # Start thread for transmitting data.
            # (Bundling multiple packets prevents USB bottlenecks.)
            self._tx_thread = threading.Thread(
                target=self._tx_loop,
                name='UART transmit')
            self._tx_thread.setDaemon(True)
            self._tx_thread.start()
        except:
            self._log.error(self._lbl + ':\n' + traceback.format_exc())

    def close(self):
        '''Close this UART port, if open.'''
        if not (self._rx_thread is None):
            self._run = False           # Stop main work loop
            self._rx_thread.join()      # Wait for thread to exit cleanly
            self._port.close()          # Closing port should stop thread

    def msg_send(self, data, blocking=False):
        '''
        Send a message over this UART port.
        Keyword arguments:
        data -- Byte string to be sent
        blocking -- Wait to finish before returning? (Default false)
        '''
        with self._tx_lock:
            if blocking:
                self._port.write(data)
            else:
                self._tx_buff += data

    def _rx_loop(self):
        '''Main loop for the receive thread.'''
        self._log.info(self._lbl + ': Rx loop start')
        rx_buff = b''   # Empty working buffer
        while self._run:
            try:
                # Attempt to read at least one byte, more if available.
                # (Wait/timeout keeps us from having to poll at crazy rates.)
                nbytes = max(1, self._port.inWaiting())
                rx_buff += self._port.read(nbytes)
                # Check if we got at least one delimiter...
                if self._delim in rx_buff:
                    rx_split = rx_buff.split(self._delim)
                    for msg in rx_split[0:-1]:      # Deliver each message
                        if len(msg) > 0:            # (Except empty ones)
                            self._callback(msg)
                    rx_buff = rx_split[-1]          # Buffer = remainder
            except:
                self._log.error(self._lbl + ':\n' + traceback.format_exc())
                sleep(1.0)              # Brief delay before retry
        self._log.info(self._lbl + ': Rx loop done')

    def _tx_loop(self):
        '''Main loop for the transmit thread.'''
        self._log.info(self._lbl + ': Tx loop start')
        while self._run:
            with self._tx_lock:
                # Grab any packet(s) from the buffer.
                data = self._tx_buff
                self._tx_buff = b''
            if len(data) > 0:
                # If there's any new data, send it.
                try:
                    self._log.debug(self._lbl + ': Sending %d bytes' % len(data))
                    sent = self._port.write(data)
                    if sent < len(data):
                        self._log.error(self._lbl + ': UART transmission failed')
                except:
                    self._log.error(self._lbl + ':\n' + traceback.format_exc())
            else:
                # Otherwise, wait a bit before polling.
                sleep(0.01)
        self._log.info(self._lbl + ': Tx loop done')

def slipDecode(data):
    '''Convert message frame to SLIP stream.'''
    return data.replace(SLIP_END, b'') \
               .replace(SLIP_ESC_END, SLIP_END) \
               .replace(SLIP_ESC_ESC, SLIP_ESC)

def slipEncode(data):
    '''Convert SLIP stream to message frame.'''
    return data.replace(SLIP_ESC, SLIP_ESC_ESC) \
               .replace(SLIP_END, SLIP_ESC_END) \
               + SLIP_END

class AsyncSLIPPort:
    '''SLIP port wrapper. Same interface as ethernet_utils::AsyncEthernetPort.'''
    def __init__(self, portname, logger, zeropad=False, verbose=False):
        '''
        Create a new "locally administered" MAC address.
        16 MSBs are 0xAE20 ("Aero"), then 32 random LSBs.
        Keyword arguments:
        portname -- UART port name (see AsyncSerialPort)
        logger -- Python logger object for error messages
        zeropad -- Enable zero-padding of short frames to at least 64 bytes (default false)
        verbose -- Enable additional status messages in log (default false)
        '''
        rand1 = randrange(65536)
        rand2 = randrange(65536)
        self.mac = b'\xAE\x20' + pack('>HH', rand1, rand2)
        self.lbl = portname
        # All other initialization...
        self._callback = None
        self._logger = logger
        self._zeropad = zeropad
        self._verbose = verbose
        self._serial = AsyncSerialPort(
            logger=logger,
            callback=self.msg_rcvd, # Thin-wrapper for callback
            msg_delim=SLIP_END)     # SLIP delimiter
        self._serial.open(portname, 921600)

    def close(self):
        '''Close this UART port.'''
        self._serial.close()

    def is_uart(self):
        '''Is this object a UART or a true Ethernet port?'''
        return True

    def set_callback(self, callback):
        '''Set callback function for received frames.'''
        self._callback = callback

    def msg_rcvd(self, slip_frm):
        '''
        Parse and deliver complete packets.
        Remove SLIP encoding and check length.
        (Expect dst MAC, src MAC, Ethertype, payload, CRC = 6+6+2+n+4).
        '''
        eth_frm = slipDecode(slip_frm)
        if self._verbose:
            self._logger.info('%s: SLIP-Rx: %u/%u bytes'
                % (self.lbl, len(eth_frm), len(slip_frm)))
        if (len(eth_frm) > 18) and (self._callback is not None):
            # Check the CRC against the expected value.
            eth_dat = eth_frm[:-4]
            rcv_crc = eth_frm[-4:]
            ref_crc = ethernet_crc(eth_dat)
            # On mismatch, log a warning but forward packet anyway.
            if (ref_crc != rcv_crc):
                [rcv_int] = unpack('<L', rcv_crc)
                [ref_int] = unpack('<L', ref_crc)
                self._logger.warning('%s: CRC mismatch, got 0x%08u expected 0x%08u'
                    % (self.lbl, rcv_int, ref_int))
            self._callback(eth_dat)

    def msg_send(self, eth_usr):
        '''
        Send frame with Dst, Src, Type, Payload (no checksum).
        Optionally zero-pad so frame + CRC is at least 64 bytes.
        '''
        if self._zeropad and len(eth_usr) < 60:
            len_pad = 60 - len(eth_usr)
            eth_usr += len_pad * b'\x00'
        # Add checksum and apply SLIP encoding.
        eth_frm = eth_usr + ethernet_crc(eth_usr)
        slip_frm = slipEncode(eth_frm)
        if self._verbose:
            self._logger.info('%s: SLIP-Tx: %u/%u bytes'
                % (self.lbl, len(eth_frm), len(slip_frm)))
        self._serial.msg_send(slip_frm)
