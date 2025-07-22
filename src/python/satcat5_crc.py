# -*- coding: utf-8 -*-

# Copyright 2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

"""
Define CRC functions for the SatCat5 project to be used in Python software.
"""

def crc16(data: bytes, poly=0x1021, init=0x0000, xor_out=0x0000) -> int:
    """
    Generic CRC-16 calculation.
    Args:
        data: Input bytes to compute CRC over.
        poly: CRC polynomial (default 0x1021 for XMODEM).
        init: Initial CRC value (default 0x0000 for XMODEM).
        xor_out: Final XOR value (default 0x0000 for XMODEM).
    Returns:
        Computed CRC as integer.
    """
    crc = init
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = (crc << 1) ^ poly
            else:
                crc <<= 1
            crc &= 0xFFFF
    return crc ^ xor_out

def crc16_xmodem(data: bytes) -> int:
    """
    CRC-16 XMODEM implementation.
    Args:
        data: Input bytes to compute CRC over.
    Returns:
        Computed CRC-16 XMODEM as integer.
    """
    return crc16(data, poly=0x1021, init=0x0000, xor_out=0x0000)