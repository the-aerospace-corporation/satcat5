# -*- coding: utf-8 -*-

# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
Design tool for CRC lookup tables

This tool generates static lookup tables for calculating Cyclic Redundancy
Check (CRC) values using the Sarwate algoirthm.  For more information:
    Stephan Brumme, "Fast CRC32"
    https://create.stephan-brumme.com/crc32/#slicing-by-8-overview

The tool can be used for any CRC algorithm, generating tables for
nybble-at-a-time ("slice-by-4") or byte-at-a-time ("slice-by-8")
operation. Code generation assumes C/C++. Parameters for common CRC16
and CRC32 configurations are included as examples.

The polynomial must be specified with the leading "1" bit to allow the
width to be inferred correctly. Input and output bit-order are specified
using the "refin" and "refout" parameters. Other initialization and output
format parameters are not included, since they do not affect the contents
of the Sarwate lookup table.  "

See also: crc16_checksum.cc
See also: eth_checksum.cc
'''

from math import floor, log2

def bitrev(x, w):
    """Given an integer X, reverse the order of the first W bits."""
    return sum([(x >> n & 1) << (w-1-n) for n in range(w)])

def byterev(x, w):
    """Given an integer X, reverse the order of bits within each byte."""
    return sum([(x >> n & 1) << (8*(n//8)+7-n%8) for n in range(w)])

class CrcTable:
    """Generate Sarwate lookup tables for a CRC code."""
    def __init__(self, poly, refin, refout):
        # Find the leading '1' in the polynomial.
        self.width  = floor(log2(poly))
        self.poly   = bitrev(poly, self.width)
        # Refin and refout have different modes:
        #   0 = No reflection, LSB-first.
        #   1 = Bitwise-reflection, MSB-first entire word.
        #   2 = Bytewise-reflection, MSB-first each byte.
        #       (Only applies to refout with N = 8)
        self.refin  = int(refin)
        self.refout = int(refout)

    def bitwise(self, value, nbits):
        """Simulate bitwise calculation of an N-bit input."""
        if self.refin: value = bitrev(value, nbits)
        crc = value
        for n in range(nbits):
            crc = (crc >> 1) ^ ((crc & 1) * self.poly)
        if self.refout == 2 and nbits == 8:
            crc = byterev(crc, self.width)
        elif self.refout:
            crc = bitrev(crc, self.width)
        return crc

    def table(self, nbits):
        """Generate and return an N-bit lookup table."""
        return [self.bitwise(x, nbits) for x in range(2**nbits)]

    def code(self, label, nbits):
        """Generate C/C++ code for an N-bit lookup table."""
        # Calculate table contents.
        tbl = self.table(nbits)
        # Determine variable type and formatting:
        if self.width <= 8:
            typ = 'u8';     cols = 8;   fmt=' 0x%02X,'
        elif self.width <= 16:
            typ = 'u16';    cols = 8;   fmt=' 0x%04X,'
        elif self.width <= 32:
            typ = 'u32';    cols = 4;   fmt=' 0x%08Xu,'
        else:
            typ = 'u64';    cols = 2;   fmt=' 0x%016Xull,'
        # Concatentate table header, contents, and footer.
        result = f'static const {typ} {label}[] = ' + '{\n'
        for r in range(len(tbl) // cols):
            result += '   '
            for c in range(cols):
                result += fmt % tbl[r*cols+c]
            result += '\n'
        result += '};\n'
        return result

if __name__ == '__main__':
    example = {
        'CRC16_KERMIT': CrcTable(0x11021, 0, 0),
        'CRC16_XMODEM': CrcTable(0x11021, 1, 2),
        'CRC32_ETHER':  CrcTable(0x104C11DB7, 0, 0),
    }
    for label, obj in example.items():
        print(obj.code(label + '_4', 4))
        print(obj.code(label + '_8', 8))
