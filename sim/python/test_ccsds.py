# -*- coding: utf-8 -*-

# Copyright 2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

"""
Unit tests for the functions defined in "satcat5_ccsds.py".
"""

import os, sys
sys.path.append(os.path.join(
    os.path.dirname(__file__), '..', '..', 'src', 'python'))
import satcat5_ccsds as ccsds

def ccsds_spp_hdr_self_test(verbose = False):
    """
    A simple test to ensure get_ccsds_spp_hdr and get_ccsds_spp_fields are 
    internally consistent.

    Args:
        verbose (bool): Default False; if True, print each test failure.

    Returns:
        int: The number of failed tests (0 = success).
    """
    ver = 2
    pkt_type = 1
    sec_flag = 0
    apid = 0x5A9
    seq_flag = 3
    seq_num = 16383
    length = 199
    pkt_bytes = b'\xA5' * length
    hdr_bytes = ccsds.get_ccsds_spp_hdr(pkt_bytes, ver, pkt_type, sec_flag, apid, seq_flag, seq_num)
    (got_ver, got_pkt_type, got_sec_flag, got_apid, got_seq_flg, got_seq_num, got_length)\
        = ccsds.get_ccsds_spp_fields(hdr_bytes)
    errcount = 0
    if len(hdr_bytes) != 6:
        if verbose: print("Incorrect SPP header length")
        errcount += 1
    if got_ver != ver:
        if verbose: print("SPP Version Mismatch")
        errcount += 1
    if pkt_type != got_pkt_type:
        if verbose: print("SPP Packet Type Mismatch")
        errcount += 1
    if sec_flag != got_sec_flag:
        if verbose: print("SPP Secondary Hdr Flag Mismatch")
        errcount += 1
    if apid != got_apid:
        if verbose: print("SPP APID Mismatch")
        errcount += 1
    if seq_flag != got_seq_flg:
        if verbose: print("SPP Sequence Flag Mismatch")
        errcount += 1
    if seq_num != got_seq_num:
        if verbose: print("SPP Sequence Number Mismatch")
        errcount += 1
    if length != got_length:
        if verbose: print("SPP Length Mismatch")
        errcount += 1
    return errcount

def ccsds_aos_hdr_self_test(verbose = False):
    """
    A simple test to ensure get_ccsds_aos_hdr and get_ccsds_aos_fields are 
    internally consistent.

    Args:
        verbose (bool): Default False; if True, print each test failure.

    Returns:
        int: The number of failed tests (0 = success).
    """
    channel_idx = 0xC8A9
    frame_count = 0xA987BC
    signal = 0x28
    hdr_bytes = ccsds.get_ccsds_aos_hdr(channel_idx, frame_count, signal)
    (got_channel_idx, got_frame_count, got_signal)\
        = ccsds.get_ccsds_aos_fields(hdr_bytes)
    errcount = 0
    if len(hdr_bytes) != 6:
        if verbose: print("Incorrect AOS header length")
        errcount += 1
    if channel_idx != got_channel_idx:
        if verbose: print("AOS Channel Index Mismatch")
        errcount += 1
    if frame_count != got_frame_count:
        if verbose: print("AOS Frame Count Mismatch")
        errcount += 1
    if signal != got_signal:
        if verbose: print("AOS Signal Mismatch")
        errcount += 1
    return errcount

def ccsds_crc_self_test(verbose):
    """
    Check CCSDS CRC against known values

    Args:
        verbose (bool): Default False; if True, print each test failure.

    Returns:
        int: The number of failed tests (0 = success).
    """
    #https://crccalc.com/?crc=211F29B11021FFFF0000102120423063&method=CRC-16/IBM-3740&datatype=hex&outtype=hex
    IN_1  = b'\x21\x1F\x29\xB1\x10\x21\xFF\xFF\x00\x00\x10\x21\x20\x42\x30\x63'
    OUT_1 = b'\x52\x50'
    # https://crccalc.com/?crc=0001&method=CRC-16/IBM-3740&datatype=hex&outtype=hex
    IN_2  = b'\x00\x01'
    OUT_2 = b'\x0D\x2E'
    # Check each reference against the ccsds_crc() function:
    errcount = 0
    if OUT_1 != ccsds.ccsds_crc(IN_1):
        if verbose: print("CRC Mismatch #1")
        errcount += 1
    if OUT_2 != ccsds.ccsds_crc(IN_2):
        if verbose: print("CRC Mismatch #2")
        errcount += 1
    return errcount

def _ccsds_wrap_test(pkt_size, frame_size, verbose=False):
    """
    Check ccsds_unwrap_m against ccsds_wrap_m

    Args:
        pkt_size (int): number of bytes in an SPP packet
        frame_size (int): number of bytes in an AOS frame

    Returns:
        int: The number of failed tests (0 = success).
    """
    errcount = 0
    pkt_bytes = b'\xAB' * pkt_size
    ref_pkt = ccsds.get_ccsds_spp_hdr(pkt_bytes, seq_num = 1234, apid = 0x123) + pkt_bytes
    frame_count = 10
    aos_frames = ccsds.ccsds_wrap_m(ref_pkt, 0, frame_count, 0, frame_size)
    rem_pkt = b''
    pkts = []
    for frame in aos_frames:
        if len(frame) != 4 + 6 + 2 + frame_size + 2:
            errcount += 1
            if verbose: print(f"{pkt_size}, {frame_size}: Frame length mismatch")
        #
        (_, got_frame_count, _) = ccsds.get_ccsds_aos_fields(frame[4:])
        if got_frame_count != frame_count:
            errcount += 1
            if verbose: print(f"{pkt_size}, {frame_size}: Frame count mistmatch: {got_frame_count} != {frame_count}")
        frame_count += 1
        #
        (pkt_list, rem_pkt) = ccsds.ccsds_unwrap_m(frame[4:], rem_pkt)
        pkts += pkt_list
    if ref_pkt not in pkts:
        errcount += 1
        if verbose: print(f"{pkt_size}, {frame_size}: Did not recover test packet!")
    pkts_len = 0
    for idx, pkt in enumerate(pkts):
        pkts_len += len(pkt)
        if idx == 0:
            if ref_pkt != pkt:
                errcount += 1
                if verbose: print(f"{pkt_size}, {frame_size}: Test packet not first!")
        else:
            (_, _, _, got_apid, _, got_seq_num, _) = ccsds.get_ccsds_spp_fields(pkt)
            if got_apid != ccsds.CCSDS_IDLE_APID:
                errcount += 1
                if verbose: print(f"{pkt_size}, {frame_size}, {idx}: Incorrect IDLE APID")
            if got_seq_num != 1234 + idx:
                errcount += 1
                if verbose: print(f"{pkt_size}, {frame_size}, {idx}: Incorrect SeqNum")
            for by in pkt[ccsds.CCSDS_SPP_HDR_LEN:]:
                if by != ccsds.CCSDS_IDLE_BYTE[0]:
                    errcount += 1

    if pkts_len % frame_size != 0:
        errcount += 1
        if verbose: print(f"{pkt_size}, {frame_size}: Invalid sum of packet lengths")
    return errcount

def ccsds_wrap_m_self_test(verbose = False):
    errcount = 0
    errcount += _ccsds_wrap_test(497, 50, verbose)
    errcount += _ccsds_wrap_test(497, 260, verbose)
    errcount += _ccsds_wrap_test(51, 50, verbose)
    errcount += _ccsds_wrap_test(50, 50, verbose)
    errcount += _ccsds_wrap_test(45, 50, verbose)
    errcount += _ccsds_wrap_test(40, 50, verbose)
    errcount += _ccsds_wrap_test(1, 50, verbose)
    return errcount

def _ccsds_wrap_b_test(bytestream_size, nbits_in_last_byte, frame_size, verbose = False):
    """
    Check ccsds_unwrap_b against ccsds_wrap_b

    Args:
        bytestream_size (int): number of bytes in the bitstream
        nbits_in_last_byte (int): number of user bits in the final byte of the stream
        frame_size (int): number of bytes in an AOS frame

    Returns:
        int: The number of failed tests (0 = success).
    """
    errcount = 0
    stream_bytes = b'\xAB' * bytestream_size
    frame_count = 10
    aos_frames = ccsds.ccsds_wrap_b(stream_bytes, nbits_in_last_byte, 0, frame_count, 0, frame_size)
    n_frames = len(aos_frames)
    got_stream = b''
    for idx, frame in enumerate(aos_frames):
        if len(frame) != 4 + 6 + 2 + frame_size + 2:
            errcount += 1
            if verbose: print(f"{bytestream_size}, {nbits_in_last_byte}, {frame_size}: Frame length mismatch")
        #
        (_, got_frame_count, _) = ccsds.get_ccsds_aos_fields(frame[4:])
        if got_frame_count != frame_count:
            errcount += 1
            if verbose: print(f"{bytestream_size}, {nbits_in_last_byte}, {frame_size}: Frame count mistmatch: {got_frame_count} != {frame_count}")
        frame_count += 1
        #
        (got_bytes, got_nbits) = ccsds.ccsds_unwrap_b(frame[4:])
        got_stream += got_bytes
        #
        if idx == n_frames - 1:
            if got_nbits != nbits_in_last_byte:
                errcount += 1
                if verbose: print(f"{bytestream_size}, {nbits_in_last_byte}, {frame_size}, {idx}: Incorrect nbits")
        else:
            if got_nbits != 8:
                errcount += 1
                if verbose: print(f"{bytestream_size}, {nbits_in_last_byte}, {frame_size}, {idx}: Incorrect nbits")
    if got_stream != stream_bytes:
        errcount += 1
        if verbose: print(f"{bytestream_size}, {nbits_in_last_byte}, {frame_size}: Did not recover test stream!")
    return errcount

def ccsds_wrap_b_self_test(verbose = False):
    errcount = 0
    for b in range(1,9):
        errcount += _ccsds_wrap_b_test(50, b, 50, verbose)
        errcount += _ccsds_wrap_b_test(50, b, 130, verbose)
        errcount += _ccsds_wrap_b_test(130, b, 50, verbose)
    return errcount

if __name__ == "__main__":
    errcount  = ccsds_crc_self_test(verbose = True)
    errcount += ccsds_spp_hdr_self_test(verbose = True)
    errcount += ccsds_aos_hdr_self_test(verbose = True)
    errcount += ccsds_wrap_m_self_test(verbose = True)
    errcount += ccsds_wrap_b_self_test(verbose = True)
    assert(errcount == 0)
