# -*- coding: utf-8 -*-

# Copyright 2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

"""
This file defines Python networking utilities for the CCSDS Advanced
Orbiting Systems Space Link Protocol (AOS) and the CCSDS Space Packet
Protocol (SPP), as defined in:
* [Blue Book 732.0-B-4](https://public.ccsds.org/Pubs/732x0b4.pdf)
* [Blue Book 133.0-B-2](https://public.ccsds.org/Pubs/133x0b2e2.pdf)
"""

import crcmod.predefined
import logging
import satcat5_uart
from struct import pack, unpack

# Define various CCSDS Constants
CCSDS_SYNCH_MARKER = b'\x1A\xCF\xFC\x1D'
CCSDS_IDLE_BYTE = b'\xA5'
CCSDS_IDLE_APID = 0x7FF
CCSDS_SPP_HDR_LEN = 6
CCSDS_SPP_IDX_MASK = 0x7FF

# If ScaPy is installed, define a very basic packet parser.
# TODO: Something more feature-rich that understands BPDU/MPDU?
try:
    from scapy.all import BitField, Packet
    from scapy.utils import PcapWriter
    SCAPY_SUPPORTED = True
    class AosPacket(Packet):
        name = "AOS"
        fields_desc = [
            BitField('id',      0, 16),
            BitField('count',   0, 24),
            BitField('signal',  0,  8)]
except:
    SCAPY_SUPPORTED = False

def get_ccsds_spp_hdr(bytes, ver = 0x0, packet_type = 0, sec_flg = 0, apid = CCSDS_IDLE_APID, seq_flg = 0x10, seq_num = 0):
    """
    Form the 6 byte CCSDS SPP header from the given fields.

    Args:
        bytes (bstr):
            Byte-string with packet contents. Used to compute the length field
        ver (3 bits):
            Notionally all zeros
        packet_type (1 bit):
            1 for telecommand/request, 0 for telemetry/reporting
        sec_flag (1 bit):
            1 if secondary header present, 0 otherwise
        apid (11 bits):
            Application Process Identifier
        seq_flag (2 bits):
            Sequence flag. 00 for continuation of data, 01 first segment, 10 last, 11 unsegment
        seq_num (14 bits):
            Packet Sequence Count

    Returns:
        bstr: Byte-string (6 bytes) of packet header
    """
    assert len(bytes) > 0
    u1  = (ver         & 0x0007) << 13
    u1 |= (packet_type & 0x0001) << 12
    u1 |= (sec_flg     & 0x0001) << 11
    u1 |= (apid        & 0x07FF)
    u2 =  (seq_flg     & 0x0003) << 14
    u2 |= (seq_num     & 0x3FFF)
    u3 =  (len(bytes) - 1) & 0xFFFF
    return pack('>HHH', u1, u2, u3)

def get_ccsds_spp_fields(hdr_bytes):
    """
    Parse the fields from the 6-byte header of a CCSDS SPP Packet.

    Args:
        hdr_bytes (bstr):
            The byte-string of the packet header. Must be at least 6 bytes

    Returns:
        tuple: a Tuple of the SPP Header Fields:
            ver (3 bits):
                The Packet Version Number. Notionally all zeros
            pkt_type (1 bit):
                1 for telecommand/request, 0 for telemetry/reporting
            sec_flag (1 bit):
                1 if secondary header present, 0 otherwise
            apid (11 bits):
                Application Process Identifier
            seq_flag (2 bits):
                Sequence flag. 00 for continuation of data, 01 first segment, 10 last, 11 unsegment
            seq_num (14 bits):
                Packet Sequence Count
            length (2 bytes):
                Length of the packet in bytes
    """
    assert len(hdr_bytes) >= 6
    ver      = (hdr_bytes[0]   & 0xE0) >> 5
    pkt_type = (hdr_bytes[0]   & 0x10) >> 4
    sec_flag = (hdr_bytes[0]   & 0x08) >> 3
    apid     =  unpack('>H', hdr_bytes[0:2])[0] & 0x07FF
    seq_flg  = (hdr_bytes[2]   & 0xC0) >> 6
    seq_num  =  unpack('>H', hdr_bytes[2:4])[0] & 0x3FFF
    length   =  unpack('>H', hdr_bytes[4:6])[0] + 1
    return (ver, pkt_type, sec_flag, apid, seq_flg, seq_num, length)

def get_ccsds_aos_hdr(channel_idx = 0x0000, frame_count = 0x000000, signal = 0x00):
    """
    Form the 6 byte CCSDS AOS header from the given fields.

    Args:
        channel_idx (2 bytes):
            The Master Channel ID (Transfer Frame Version Number [2 bits] + Spacecraft ID [8 bits]
            concatenated with the Virtual Channel ID (6 bits)
        frame_count (3 bytes):
            Virtual Channel Frame Count is the number of frames transmitted with this virtual ID
        signal (1 byte):
            Concatenation of the Replay Flag (1 bit), the VC Frame Count Usage Flag (1 bit), a
            Reserved Field (2 bits), and the VC Frame Count Cycle (4 bits)

    Returns:
        bstr: Byte-string (6 bytes) of frame header
    """
    return channel_idx.to_bytes(2, 'big') \
        + frame_count.to_bytes(3, 'big') \
        + signal.to_bytes(1, 'big')

def get_ccsds_aos_fields(hdr_bytes):
    """
    Parse the fields from the given 6-byte CCSDS AOS header

    Args:
        hdr_bytes:
            Byte-string (6 bytes) of frame header

    Returns:
        tuple: a tuple of the AOS Header Fields:
            channel_idx (2 bytes):
                The Master Channel ID (Transfer Frame Version Number [2 bits] + Spacecraft ID [8 bits]
                concatenated with the Virtual Channel ID (6 bits)
            frame_count (3 bytes):
                Virtual Channel Frame Count is the number of frames transmitted with this virtual ID
            signal (1 byte):
                Concatenation of the Replay Flag (1 bit), the VC Frame Count Usage Flag (1 bit), a
                Reserved Field (2 bits), and the VC Frame Count Cycle (4 bits)
    """
    channel_idx = unpack('>H', hdr_bytes[0:2])[0]
    frame_count = unpack('>L', b'\x00' + hdr_bytes[2:5])[0] & 0xFFFFFF
    sig = hdr_bytes[5]
    return (channel_idx, frame_count, sig)

def ccsds_crc(frame_bytes):
    """
    Computes the Frame Error Control Field from the given bytes. Uses polynomial
    X^16 + X^12 + X^5 + 1 (CRC-16 CCIT False, IBM 3740)

    Args:
        frame_bytes:
            Byte-string of the frame

    Returns:
        bstr: Byte-string (2 bytes) of the computed FECF
    """
    crc16 = crcmod.predefined.Crc('crc-ccitt-false')
    crc16.update(frame_bytes)
    return crc16.digest()

def ccsds_wrap_m(spp_pkt, ch_idx = 0, fr_count = 0, sig = 0, transfer_frame_size=-1):
    """
    Wraps a CCSDS SPP Packet in one or more AOS Frames and appends a CCSDS Synch Marker to each AOS frame.
    If transfer_frame_size is not specified, then the packet is wrapped in a single AOS frame with no padding.
    If transfer_frame_size is specified and the size of the packet is:
        - smaller than than the frame size, then the frame will contain the given packet and an Idle SPP Packet
        - larger than than the frame size, then the packet will be split over multiple frames,
          with the final frame containing Idle padding

    Args:
        spp_pkt:
            Byte-string of the CCSDS SPP Packet to be wrapped
        ch_idx (2 bytes):
            The concatenation of the Master and Virtual Channel IDs of the AOS Frame (Default 0)
        fr_count (3 bytes):
            The number of frames already transmitted with this Virtual Channel ID (Default 0)
        sig (1 byte):
            The AOS Signaling Field (Default 0)
        transfer_frame_size (int):
            If > 0, the fixed number of bytes in an AOS Frame. If < 0, then frame size can vary (Default)

    Returns:
        list: A bstr list containing one or more AOS Frame byte strings, with Synch Markers
    """
    # if transfer frames aren't fixed length, just wrap the full packet
    if transfer_frame_size < 0:
        aos_hdr = get_ccsds_aos_hdr(ch_idx, fr_count, sig)
        aos_frame = aos_hdr + b'\x00\x00' + spp_pkt
        return [CCSDS_SYNCH_MARKER + aos_frame + ccsds_crc(aos_frame)]
    # if transfer frames are fixed length, we must split/idle-pad the packet over one or more frames
    aos_frames = []
    rem_pdu = spp_pkt[:]
    seq_num = get_ccsds_spp_fields(spp_pkt)[5] + 1
    idx = 0   # tracks the index of the first SPP packet beginning within a frame
    while len(rem_pdu) > 0:
        aos_hdr = get_ccsds_aos_hdr(ch_idx, fr_count, sig)
        fr_count += 1
        if len(rem_pdu) >= transfer_frame_size: # frame is fully filled by this packet
            aos_frame = aos_hdr + (CCSDS_SPP_IDX_MASK & idx).to_bytes(2, 'big') \
                + rem_pdu[0:transfer_frame_size]
            aos_frames.append(CCSDS_SYNCH_MARKER + aos_frame + ccsds_crc(aos_frame))
            rem_pdu = rem_pdu[transfer_frame_size:] # remainder of PDU used in next iteration
            idx = CCSDS_SPP_IDX_MASK
        elif len(rem_pdu) < transfer_frame_size - CCSDS_SPP_HDR_LEN: # fill with a single idle packet
            idle_len = transfer_frame_size - len(rem_pdu) - CCSDS_SPP_HDR_LEN # > 0
            idle_pkt = get_ccsds_spp_hdr(CCSDS_IDLE_BYTE*idle_len, apid = CCSDS_IDLE_APID, seq_num = seq_num)\
                     + CCSDS_IDLE_BYTE*idle_len
            if idx != 0:           # if idx == 0, then this is the first packet and first frame.
                idx = len(rem_pdu) # if not, the idle packet is the first packet beginning in this frame
            aos_frame = aos_hdr + (CCSDS_SPP_IDX_MASK & idx).to_bytes(2, 'big') \
                + rem_pdu + idle_pkt
            aos_frames.append(CCSDS_SYNCH_MARKER + aos_frame + ccsds_crc(aos_frame))
            rem_pdu = b'' # no remainder, we used up the full PDU
        else: # need to append an idle packet, but the idle packet spills over into another frame.
            idle_f1_bytes = transfer_frame_size - len(rem_pdu)
            idle_len = idle_f1_bytes + transfer_frame_size - CCSDS_SPP_HDR_LEN # fill f1 + another full frame
            idle_pkt = get_ccsds_spp_hdr(CCSDS_IDLE_BYTE*idle_len, apid = CCSDS_IDLE_APID, seq_num = seq_num)\
                     + CCSDS_IDLE_BYTE*idle_len
            if idx != 0:           # if idx == 0, then this is the first packet and first frame.
                idx = len(rem_pdu) # if not, the idle packet is the first packet beginning in this frame
            aos_frame = aos_hdr + (CCSDS_SPP_IDX_MASK & idx).to_bytes(2, 'big') \
                + rem_pdu + idle_pkt[0:idle_f1_bytes]
            aos_frames.append(CCSDS_SYNCH_MARKER + aos_frame + ccsds_crc(aos_frame))
            rem_pdu = idle_pkt[idle_f1_bytes:] # remainder of the spilling idle packet used in next iteration
            idx = CCSDS_SPP_IDX_MASK
    return aos_frames

def ccsds_unwrap_m(aos_frame, rem_pkt = b''):
    """
    Attempts to unwraps one or more CCSDS SPP Packets contained in a given frame. Packets can be split
    over multiple frames, so this may only yield a partial packet. Also attempts to reconstruct partial
    packets obtained from previous frames.

    Args:
        aos_frame:
            Byte-string of the CCSDS AOS Frame to be unwrapped (no synch marker)
        rem_pkt:
            Byte-string of the current partial packet obtained from previous frames. Default is len 0

    Returns:
        tuple: a tuple containing full and partial SPP packets:
            list: 
                A bstr list containing zero or more SPP packet byte strings
            bstr: 
                The current partial packet obtained from this and previous frames. May be length 0.
    """
    spp_pkts = []
    pdu = aos_frame[8:-2]
    transfer_frame_size = len(pdu)
    # get the index of the first packet beginning in this frame
    idx = min(unpack('>H', aos_frame[6:8])[0], len(pdu))
    # any bytes prior to idx belong to the previous packet
    rem_pkt += pdu[0:idx]
    # check if we can reconstruct the previous packet
    if len(rem_pkt) >= CCSDS_SPP_HDR_LEN:
        pkt_len = get_ccsds_spp_fields(rem_pkt)[6] + CCSDS_SPP_HDR_LEN
        if len(rem_pkt) == pkt_len:
            spp_pkts.append(rem_pkt)
            rem_pkt = b''
    # parse the rest of the frame
    while idx < transfer_frame_size:
        # check if we can reconstruct a full packet from the current frame's PDU,
        # if not, it becomes rem_pkt and needs the next frame to reconstruct.
        # the frame may contain multipe full packets or none.
        if len(pdu[idx:]) >= CCSDS_SPP_HDR_LEN:
            pkt_len = get_ccsds_spp_fields(pdu[idx:])[6] + CCSDS_SPP_HDR_LEN
            if idx + pkt_len <= transfer_frame_size:
                spp_pkts.append(pdu[idx : idx+pkt_len])
                rem_pkt = b''
                idx += pkt_len
            else:
                rem_pkt = pdu[idx:]
                break
        else:
            rem_pkt = pdu[idx:]
            break
    return (spp_pkts, rem_pkt)

def ccsds_wrap_b(bytestream, nbits_in_last_byte = 8, ch_idx = 0, fr_count = 0, sig = 0, transfer_frame_size=-1):
    """
    Wraps a bitstream in one or more AOS Frames and appends a CCSDS Synch Marker to each AOS frame.
    If transfer_frame_size is not specified, then the bitstream is wrapped in a single AOS frame with no padding.
    If transfer_frame_size is specified and the size of the bitstream is:
        - smaller than than the frame size, then the frame will contain the given packet and an Idle SPP Packet
        - larger than than the frame size, then the packet will be split over multiple frames,
          with the final frame containing Idle padding

    Args:
        bytestream:
            Byte-string of user data. the last byte may contain filler bits, specified by nbits_in_last_byte.
        nbits_in_last_byte (int 1,2,...,8)
            The numebr of user data bits in the last byte. (Default 8, i.e. all user bits)
        ch_idx (2 bytes):
            The concatenation of the Master and Virtual Channel IDs of the AOS Frame (Default 0)
        fr_count (3 bytes):
            The number of frames already transmitted with this Virtual Channel ID (Default 0)
        sig (1 byte):
            The AOS Signaling Field (default 0)
        transfer_frame_size (int):
            If > 0, the fixed number of bytes in an AOS Frame. If < 0, frame size can vary (Default)

    Returns:
        list: A bstr list containing one or more AOS Frame byte strings, with Synch Markers
    """
    # if transfer frame size is variable, then just wrap the bytestream in an AOS Frame
    if transfer_frame_size < 0:
        # index of last valid user bit = length in bits - 1
        idx_bit = 8*len(bytestream) - (8 - nbits_in_last_byte) - 1
        aos_frame = get_ccsds_aos_hdr(0, fr_count, 0) \
            + idx_bit.to_bytes(2, 'big') + bytestream
        full_frame = CCSDS_SYNCH_MARKER + aos_frame + ccsds_crc(aos_frame)
        return [full_frame]
    # if transfer frame size is fixed, then send the bytestream over one or more AOS Frames
    # with Idle padding
    idx_byte= 0
    full_frames = []
    while idx_byte < len(bytestream):
        p_len = min(len(bytestream[idx_byte:]), transfer_frame_size)
        pdu = bytestream[idx_byte : idx_byte + p_len]\
            + CCSDS_IDLE_BYTE * (transfer_frame_size - p_len) # may be zero
        # index of last valid user bit = length in bits - 1. If it is the last frame,
        # then the last byte may not be all data bits. Otherwise, all bits are data.
        idx_bit = 8*p_len - 1 
        if p_len == len(bytestream[idx_byte:]): 
            idx_bit -= (8 - nbits_in_last_byte)

        idx_byte += p_len
        aos_frame = get_ccsds_aos_hdr(ch_idx, fr_count, sig) \
            + idx_bit.to_bytes(2, 'big') + pdu
        full_frame = CCSDS_SYNCH_MARKER + aos_frame + ccsds_crc(aos_frame)
        fr_count += 1
        full_frames.append(full_frame)
    return full_frames

def ccsds_unwrap_b(aos_frame):
    """
    Unwraps a bitstream contained in a given frame and returns only valid user data.

    Args:
        aos_frame:
            Byte-string of the CCSDS AOS Frame to be unwrapped (no synch marker)

    Returns:
        tuple: a tuple containing the bytestream and bit indicator:
            bstr: 
                A bstr containing the user data as bytes
            int (1 thru 8): 
                The number of user bits in the final byte. The rest of the final byte is don't care.
    """
    # b_pdu = binary payload
    pdu = aos_frame[8:-2]
    # idx of last valid user bit = length in bits - 1
    idx_bit = unpack('>H', aos_frame[6:8])[0]
    nbits_in_last_byte = (idx_bit % 8) + 1
    # idx of last valid user byte = (length in bits - 1) // 8
    # = length in bytes - 1
    idx_byte = idx_bit >> 3 
    # upper limit of range is the length of valid user bytes
    pdu_byte_ul = min(idx_byte + 1, len(pdu))
    # return the bytestream and indicate the final bit
    return (pdu[:pdu_byte_ul], nbits_in_last_byte)

class AsyncCCSDSPort:
    """CCSDS port wrapper. Uses CCSDS Blue Book 131.0-B-5 Frame Synchronization Marker
    with CCSDS Blue Book 732.0-B-4 Transfer Frames to
    send/receive CCSDS Blue Book 133.0-B-2 Space Protocol Packets"""
    def __init__(self, portname, logger=None, baudrate=921600, transfer_frame_size=-1, protocol_data_unit="M", verbose=False):
        """
        Construct a new AsyncCCSDSPort object.
        Args:
            portname (str):
                UART port name (see AsyncSerialPort, list_uart_interfaces)
            logger (Logger or None):
                Python logger object for error messages.
                Default is None, which prints a message to the console.
            baudrate (int):
                Baud rate for the underlying UART, in bits/sec.  Default 921,600.
            transfer_frame_size (int):
                The number of bytes in each AOS Transfer Frame Data Field. If < 0, then frame size can vary (default)
            protocol_data_unit (str):
                Either "M" or "B" to denote Multiplexing or Bitstream Protocol Data Unit.
                M_PDU wraps CCSDS SPP Packets and B_PDU wraps bitstreams. Impacts the behavior
                of msg_send and msg_rcvd. Default M_PDU
            verbose (bool):
                Enable additional status messages in log? (Default = False)
        """
        self.lbl = portname
        # All other initialization...
        if logger is None:
            logger = logging.getLogger(__name__)
        self._callback = None
        self._logger = logger
        self._pcap = None
        self._verbose = verbose
        try:
            self._pdu = protocol_data_unit[0].upper()
            assert(self._pdu == "M" or self._pdu == "B")
        except:
            self._logger.error("invalid PDU descriptor")
            return
        # AOS Header = 6 bytes
        # M_PDU or B_PDU header = 2 bytes
        # Frame Error Control Field = 2 bytes
        if transfer_frame_size > 0:
            self._transfer_frame_size = transfer_frame_size - 2
            self._full_frame_size = 6 + transfer_frame_size + 2
        else:
            self._transfer_frame_size = -1
            self._full_frame_size = -1
        self.rem_packet = b''
        self._serial = None
        self._prev_partial_frame = b''
        self._prev_partial_packet = b''
        self._frame_tx_count = 0
        self._frame_rx_count = -1
        self._serial = satcat5_uart.AsyncSerialPort(
            logger=self._logger,
            callback=self.msg_rcvd, # Thin-wrapper for callback
            msg_delim=CCSDS_SYNCH_MARKER) # CCSDS 131.0-B-5 delimiter
        self._serial.open(self.lbl, baudrate) 

    def close(self):
        """Close this UART port."""
        if callable(getattr(self._serial, 'close', None)):
            self._serial.close()
        if self._pcap is not None:
            self._pcap.flush()
            self._pcap.close()
            self._pcap = None

    def set_callback(self, callback):
        """
        Set "callback" function that is called for each received packet or bitstream.
        The function should accept: 
            - a single byte-string argument, containing the full SPP Packet, if M_PDU, or
            - a byte-string argument, containing the full B_PDU data field, and
                an integer denoting how many data bits are in the last byte (1 thru 8).

        Args:
            callback (function): The new callback function.
        """
        self._callback = callback

    def set_pcap(self, filename):
        """
        Enable packet-capture on this interface, recording all incoming and
        outgoing frames to the designated PCAP or PCAPNG file.  Use of this
        method requires ScaPy to be installed.

        Args:
            filename (string): Location for the output file.
        """
        # Use linktype = 147 (user-defined) so it can load in Wireshark
        # without attempting to parse each one as an Ethernet frame.
        if SCAPY_SUPPORTED:
            self._pcap = PcapWriter(filename, linktype=147)

    def msg_rcvd(self, aos_frame):
        """
        Parse a complete AOS frame, and notify the designated callback function.
        This function usually acts as a callback for an AsyncSerialPort object.

        The input is a byte-string containing a single CCSDS AOS frame. Frames contain
        one M_PDU (one or more partial or complete CCSDS SPP Packets) or M_BDU (bitstream).
        The frame undergoes several checks, then the payload is parsed.
        For an M_PDU:
            The AOS framing is removed and SPP Packets are reassembled. 
            Each reassembled packets is passed to the specified callback function.
        For a B_PDU:
            The AOS framing and idle padding is removed, then the user data is passed to the callback function.

        Args:
            aos_frame (bstr): A single CCSDS AOS frame as a Byte String.
        """
        # catch fixed length frames that contain CCSDS_SYNCH_MARKER in their data field.
        # if frames are not fixed size, only the else condition will trigger.
        if self._full_frame_size > 0 and len(aos_frame) != self._full_frame_size:
            self._logger.warning('Unexpected frame length')
            # concatenate this partial frame with the previously received partial frame
            aos_frame = self._prev_partial_frame + aos_frame
            # if the concatenated partial frames forms a full frame, then process it!
            # if the length of the concatenated frames is too large, then discard it.
            # if the length is too short, add a synch marker and store the partial frame
            # so we can try to reconstruct the frame on the next call of msg_rcvd.
            if len(aos_frame) == self._full_frame_size:
                pass
            elif len(aos_frame) + len(CCSDS_SYNCH_MARKER) > self._full_frame_size:
                self._prev_partial_frame = b''
                return
            else:
                self._prev_partial_frame = aos_frame + CCSDS_SYNCH_MARKER
                return
        else:
            self._prev_partial_frame = b''
        if len(aos_frame) == 0:
            return
        # aos_frame is now a full frame (hdr + pdu + crc)
        frm_bytes = aos_frame[:-2]
        rcv_crc   = aos_frame[-2:]
        ref_crc   = ccsds_crc(frm_bytes)
        # If packet capture is enabled, log it now.
        if self._pcap is not None:
            self._pcap.write(AosPacket(frm_bytes))
        # discard frames and partial packets with failed CRC
        if ref_crc != rcv_crc:
            [rcv_int] = unpack('<H', rcv_crc)
            [ref_int] = unpack('<H', ref_crc)
            self._logger.warning('%s: CRC mismatch, got 0x%04u expected 0x%04u'
                    % (self.lbl, rcv_int, ref_int))
            self.rem_packet = b''
            self.rem_len = 0
            return
        # check the frame's virtual frame count
        (_, rx_frame_count, _) = get_ccsds_aos_fields(aos_frame)
        self._frame_rx_count += 1
        if self._frame_rx_count != rx_frame_count:
            self._logger.warning(f'Non-sequential frame count received: {rx_frame_count} (exp {self._frame_rx_count})')
            self._frame_rx_count = rx_frame_count
        if self._pdu == "M":
            # m_pdu = concatenated packets
            spp_pkts, self.rem_packet = ccsds_unwrap_m(aos_frame, self.rem_packet)
            # spp_pkts contains 0 or more packets, do the callback function on each pkt
            for pkt in spp_pkts:
                self._callback(pkt)
        elif self._pdu == "B":
            b_pdu, nbits = ccsds_unwrap_b(aos_frame)
            self._callback(b_pdu, nbits)
        else:
            self._logger.error("invalid PDU descriptor")
            return

    def msg_send(self, msg, blocking=False, nbits_in_last_byte = 8):
        """
        Send a message as a CCSDS AOS frame with Synch word. Expects
        an SPP packet if M_PDU or a bytestream if B_PDU

        Args:
            msg (bstr):
                Byte string of data (either an SPP packet or a bytestream)
            blocking (bool):
                Wait to finish before returning? (Default false)
            nbits_in_last_byte (int between 1 and 8, inclusive):
                Only used when the Data Field is Bitstream PDU (B_PDU).
                The number of bits in the last byte of bytestream that are user data. 
                Default: all bits are assumed to be user data.
        """
        if len(msg) == 0:
            return
        if self._pdu == "M":
            aos_frames = ccsds_wrap_m(msg,
                                ch_idx = 0x4000,
                                fr_count = self._frame_tx_count,
                                sig = 0,
                                transfer_frame_size = self._transfer_frame_size)
        elif self._pdu == "B":
            aos_frames = ccsds_wrap_b(msg, nbits_in_last_byte,
                                  ch_idx = 0x4001,
                                  fr_count = self._frame_tx_count,
                                  sig = 0,
                                  transfer_frame_size = self._transfer_frame_size)
        else:
            self._logger.error("invalid PDU descriptor")
            return
        self._frame_tx_count += len(aos_frames)
        for aos_frame in aos_frames:
            if self._verbose:
                self._logger.info('%s: CCSDS-Tx: %u/%u bytes (msg/marker+frame)'
                    % (self.lbl, len(msg), len(aos_frame)))
            self._serial.msg_send(aos_frame, blocking)
            if self._pcap is not None:
                self._pcap.write(AosPacket(aos_frame))
