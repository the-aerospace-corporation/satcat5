# -*- coding: utf-8 -*-

# Copyright 2021-2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

"""
Define asynchronous, frame-based serial port interfaces and SLIP conversion
functions.  Messages are assumed to use fixed delimiter characters.
"""

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
    """
    Construct a list of all available UART interface.

    Returns:
        A dictionary of UART interfaces.
        Keys are human-readable names.
        Values are ID-strings suitable for passing to serial.Serial.
        (Formatting of the ID-strings is OS-specific)
    """
    result = {}
    for dev in lp.comports():
        os_name = dev.device
        label = os_name + ': ' + dev.description
        result[label] = os_name
    return result

def ethernet_crc(pkt):
    """
    Calculate Ethernet-FCS (CRC32), ready to be concatentated
    with the rest of the frame contents to form a complete packet.

    Args:
        pkt (bstr): Frame contents as a byte-string.

    Returns:
        bstr: CRC32 of pkt, as a byte-string.
    """
    crc_int = crc32(pkt) & 0xFFFFFFFF
    return pack('<L', crc_int)

def generate_random_macaddr():
    """
    Create a new "locally administered" MAC address.
    16 MSBs are 0xAE20 ("Aero"), then 32 random LSBs.

    Returns:
        bstr: Byte-string containing the new address (length = 6).
    """
    rand1 = randrange(65536)
    rand2 = randrange(65536)
    return b'\xAE\x20' + pack('>HH', rand1, rand2)

def crc_self_test(verbose=False):
    """
    Self-test function to verify CRC parameters.

    Args:
        verbose (bool): Default False; if True, print each test failure.

    Returns:
        int: The number of failed tests (0 = success).
    """
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
        if verbose: print("CRC Mismatch #1")
        errcount += 1
    if REF2 != ethernet_crc(PKT2):
        if verbose: print("CRC Mismatch #2")
        errcount += 1
    return errcount

class AsyncSerialPort:
    """Frame-based UART class with adjustable delimiter."""
    def __init__(self, logger, callback, msg_delim=b'\n'):
        """
        Initialize member variables.

        Args:
            logger (Logger):
                Logger object, i.e., logging.getLogger(xx)
            callback (function):
                Function to be called for each received frame (or None).
                See "set_callback" for additional details.
            msg_delim (string):
                Character(s) that mark inter-frame boundaries, default '\n'.
                Use None or empty string for no delimiter and callback will
                be called with any received bytes.
        """
        self._baudrate = 0
        self._callback = None
        self._delim = msg_delim
        self._lbl = 'Placeholder'
        self._log = logger
        self._run = False
        self._tx_lock = threading.Lock()
        self._tx_buff = b''
        self.set_callback(callback)
        # Create placeholder Serial object and worker threads.
        self._port = serial.Serial()
        self._rx_thread = None
        self._tx_thread = None

    def set_callback(self, callback):
        """
        Set "callback" function that is called for each received block of data.
        The function should accept a single byte-string argument, which
        contains the data between "delim" markers set in the constructor.

        Args:
            callback (function): New callback function (see above)
        """
        self._callback = callback

    def open(self, portname, baudrate=921600):
        """
        Open the specified UART port.

        Args:
            portname (string):
                Name of the UART interface, suitable for Serial constructor.
                Format of this name depends on the host operating system.
                See also: list_uart_interfaces()
            baudrate (int):
                Baud rate of the UART port, in bits per second. (Default 921,600)
        """
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
        """Close this UART port, if open."""
        if not (self._rx_thread is None):
            self._run = False           # Stop main work loop
            self._rx_thread.join()      # Wait for thread to exit cleanly
            self._port.close()          # Closing port should stop thread

    def msg_send(self, data, blocking=False):
        """
        Send a message over this UART port.

        Args:
            data (bstr):
                Message to be sent over UART, as a byte-string.
            blocking (bool):
                Wait to finish before returning? (Default false)
        """
        with self._tx_lock:
            if blocking:
                self._port.write(data)
            else:
                self._tx_buff += data

    def _rx_loop(self):
        """Main loop for the receive thread."""
        self._log.info(self._lbl + ': Rx loop start')
        rx_buff = b''   # Empty working buffer
        while self._run:
            try:
                # Attempt to read at least one byte, more if available.
                # (Wait/timeout keeps us from having to poll at crazy rates.)
                nbytes = max(1, self._port.inWaiting())  # Always try reading at least 1 byte
                rx_buff += self._port.read(nbytes)  # read will timeout if no bytes, this prevents busy-waiting
                if not rx_buff:
                    continue
                # If no delimiter, issue callback every time we have at least 1 byte.
                # Otherwise, check if we got at least one delimiter.
                if not self._delim:  # '' or None
                    self._callback(rx_buff)
                    rx_buff = b''
                elif self._delim in rx_buff:
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
        """Main loop for the transmit thread."""
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
    """
    Convert SLIP byte-stream to a message frame.

    Args:
        data (bstr): Byte-string containing any number of SLIP frames.

    Returns:
        bstr: Concatenated frame contents after SLIP decoding.
    """
    return data.replace(SLIP_END, b'') \
               .replace(SLIP_ESC_END, SLIP_END) \
               .replace(SLIP_ESC_ESC, SLIP_ESC)

def slipEncode(data):
    """
    Convert a message frame to a SLIP byte-stream.

    Args:
        data (bstr): Byte-string containing a single frame.

    Returns:
        bstr: SLIP-encoded frame, plus end-of-frame token.
    """
    return data.replace(SLIP_ESC, SLIP_ESC_ESC) \
               .replace(SLIP_END, SLIP_ESC_END) \
               + SLIP_END

def slipEncodeFCS(eth_usr, zeropad=False):
    """
    Calculate and append FCS before calling slipEncode().

    Args:
        eth_usr (bstr):
            Byte-string with frame contents.
            For Ethernet, this is Dst + Src + Type + Payload.
        zeropad (bool):
            Pad length to Ethernet minimum of 64 bytes?

    Returns:
        bstr: Byte-string containing SLIP-encoded frame.
    """
    # Zero-pad to minimum length if requested.
    if zeropad and len(eth_usr) < 60:
        len_pad = 60 - len(eth_usr)
        eth_usr += len_pad * b'\x00'
    # Add checksum and apply SLIP encoding.
    eth_frm = eth_usr + ethernet_crc(eth_usr)
    return slipEncode(eth_frm)

class AsyncSLIPPort:
    """SLIP port wrapper. Same interface as ethernet_utils::AsyncEthernetPort."""
    def __init__(self, portname, logger, baudrate=921600, eth_fcs=True, drop_fcs=True, zeropad=False, verbose=False):
        """
        Construct a new AsncSLIPPort object.
        Args:
            portname (str):
                UART port name (see AsyncSerialPort, list_uart_interfaces)
            logger (Logger):
                Python logger object for error messages
            baudrate (int):
                Baud rate for the underlying UART, in bits/sec.  Default 921,600.
            eth_fcs (bool):
                If true, check and remove FCS from received frames. (Default)
                Otherwise, forward received frames verbatim.
            drop_fcs (bool):
                If true, drop frames that fail FCS check.
                This flag has no effect if eth_fcs = False.
            zeropad (bool):
                If true, zero-pad outgoing frames to at least 64 bytes.
                Otherwise , allow outgoing frames of any size (default).
            verbose (bool):
                Enable additional status messages in log? (Default = False)
        """
        self.mac = generate_random_macaddr()
        self.lbl = portname
        # All other initialization...
        self._callback = None
        self._eth_fcs = eth_fcs
        self._drop_fcs = drop_fcs
        self._logger = logger
        self._zeropad = zeropad
        self._verbose = verbose
        self._serial = AsyncSerialPort(
            logger=logger,
            callback=self.msg_rcvd, # Thin-wrapper for callback
            msg_delim=SLIP_END)     # SLIP delimiter
        self._serial.open(portname, baudrate)

    def close(self):
        """Close this UART port."""
        self._serial.close()

    def is_uart(self):
        """Is this object a UART or a true Ethernet port?"""
        return True

    def set_callback(self, callback):
        """
        Set "callback" function that is called for each received frame.
        The function should accept a single byte-string argument, which
        contains the raw-Ethernet header and contents but not the FCS.

        Args:
            callback (function): The new callback function.
        """
        self._callback = callback

    def msg_rcvd(self, slip_frm):
        """
        Parse a complete packet, and notify the designated callback function.
        This function usually acts as a callback for an AsyncSerialPort object.

        The input is a SLIP-encoded byte-string containing a single frame.  The
        SLIP code is always removed from the output.  In FCS mode, this function
        also verifies the packet integrity and removes the FCS field.  Otherwise,
        the decoded packet is forwarded verbatim.

        Args:
            slip_frm (bstr): A single SLIP-encoded frame.
        """
        eth_frm = slipDecode(slip_frm)
        if self._verbose:
            self._logger.info('%s: SLIP-Rx: %u/%u bytes'
                % (self.lbl, len(eth_frm), len(slip_frm)))
        if self._callback is None:
            # No callback; discard this frame.
            return
        elif not self._eth_fcs:
            # FCS mode disabled, forward verbatim.
            self._callback(eth_frm)
        elif len(eth_frm) >= 18:
            # Check the FCS against the expected value.
            eth_dat = eth_frm[:-4]
            rcv_crc = eth_frm[-4:]
            ref_crc = ethernet_crc(eth_dat)
            # Deliver packet?
            if ref_crc == rcv_crc:
                # Good FCS -> Always deliver.
                self._callback(eth_dat)
            elif self._drop_fcs:
                # Bad FCS + Drop flag -> Drop
                return
            else:
                # Deliver anyway, but issue a warning.
                [rcv_int] = unpack('<L', rcv_crc)
                [ref_int] = unpack('<L', ref_crc)
                self._logger.warning('%s: CRC mismatch, got 0x%08u expected 0x%08u'
                    % (self.lbl, rcv_int, ref_int))
                self._callback(eth_dat)

    def msg_send(self, eth_usr, blocking=False):
        """
        Send an SLIP-encoded Ethernet frame.
        Frames shorter than the minimum size will be zero-padded,
        if that option was enabled in the constructor.

        Args:
            eth_usr (bstr):
                Byte string containing entire frame except FCS.
                (i.e., If using ScaPy packet objects, call "pkt.raw()".)
                Should contain Dst + Src + Type + Payload
            blocking (bool):
                Wait to finish before returning? (Default false)
        """
        slip_frm = slipEncodeFCS(eth_usr, self._zeropad)
        if self._verbose:
            self._logger.info('%s: SLIP-Tx: %u/%u bytes'
                % (self.lbl, len(eth_usr), len(slip_frm)))
        self._serial.msg_send(slip_frm, blocking)

class AsyncSLIPWriteOnly:
    """Write-only variant of AsyncSLIPPort."""
    def __init__(self, port_obj, zeropad=False):
        """
        Create wrapper for the given AsyncSerialPort.

        Args:
            port_obj (AsyncSerialPort):
                The AsyncSerialPort object to be wraped.
            zeropad (bool):
                Pad length to Ethernet minimum of 64 bytes?
        """
        self.mac   = generate_random_macaddr()
        self.lbl   = port_obj._lbl
        self._port = port_obj
        self._zpad = zeropad

    def is_uart(self):
        """Is this object a UART or a true Ethernet port?"""
        return True

    def msg_send(self, eth_usr, blocking=False):
        """
        Send a SLIP-encoded frame.
        Optionally zero-pad so frame + CRC is at least 64 bytes.

        Args:
            eth_usr (bstr):
                Ethernet frame with Dst, Src, Type, Payload (no checksum).
            blocking (bool):
                Wait to finish before returning? (Default false)
        """
        slip_frm = slipEncodeFCS(eth_usr, self._zpad)
        self._port.msg_send(slip_frm, blocking)
