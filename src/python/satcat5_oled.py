#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2023 The Aerospace Corporation
#
# This file is part of SatCat5.
#
# SatCat5 is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# SatCat5 is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY  without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.

"""
This file defines a text-rendering utility for the SSD1306 OLED display,
which is controlled over I2C.  It accepts most regular ASCII characters,
with anything else rendered as an empty space.
"""

from time import sleep
from satcat5_i2c import I2cAddress, I2cController

# A simple 8x8 font in the preferred format for the SSD1306.
# Each byte is one column, with the bottom pixel in the MSB.
# Derived from Daniel Hepper's public domain bitmap font:
# https://github.com/dhepper/font8x8/blob/master/font8x8_basic.h
SSD1306_SPACE = bytes(8)
SSD1306_FONT = {
    '!':  b'\x00\x00\x06\x5F\x5F\x06\x00\x00',
    '"':  b'\x00\x03\x03\x00\x03\x03\x00\x00',
    '#':  b'\x14\x7F\x7F\x14\x7F\x7F\x14\x00',
    '$':  b'\x24\x2E\x6B\x6B\x3A\x12\x00\x00',
    '%':  b'\x46\x66\x30\x18\x0C\x66\x62\x00',
    '&':  b'\x30\x7A\x4F\x5D\x37\x7A\x48\x00',
    "'":  b'\x04\x07\x03\x00\x00\x00\x00\x00',
    '(':  b'\x00\x1C\x3E\x63\x41\x00\x00\x00',
    ')':  b'\x00\x41\x63\x3E\x1C\x00\x00\x00',
    '*':  b'\x08\x2A\x3E\x1C\x1C\x3E\x2A\x08',
    '+':  b'\x08\x08\x3E\x3E\x08\x08\x00\x00',
    ',':  b'\x00\x80\xE0\x60\x00\x00\x00\x00',
    '-':  b'\x08\x08\x08\x08\x08\x08\x00\x00',
    '.':  b'\x00\x00\x60\x60\x00\x00\x00\x00',
    '/':  b'\x60\x30\x18\x0C\x06\x03\x01\x00',
    '0':  b'\x3E\x7F\x71\x59\x4D\x7F\x3E\x00',
    '1':  b'\x40\x42\x7F\x7F\x40\x40\x00\x00',
    '2':  b'\x62\x73\x59\x49\x6F\x66\x00\x00',
    '3':  b'\x22\x63\x49\x49\x7F\x36\x00\x00',
    '4':  b'\x18\x1C\x16\x53\x7F\x7F\x50\x00',
    '5':  b'\x27\x67\x45\x45\x7D\x39\x00\x00',
    '6':  b'\x3C\x7E\x4B\x49\x79\x30\x00\x00',
    '7':  b'\x03\x03\x71\x79\x0F\x07\x00\x00',
    '8':  b'\x36\x7F\x49\x49\x7F\x36\x00\x00',
    '9':  b'\x06\x4F\x49\x69\x3F\x1E\x00\x00',
    ':':  b'\x00\x00\x66\x66\x00\x00\x00\x00',
    ';':  b'\x00\x80\xE6\x66\x00\x00\x00\x00',
    '<':  b'\x08\x1C\x36\x63\x41\x00\x00\x00',
    '=':  b'\x24\x24\x24\x24\x24\x24\x00\x00',
    '>':  b'\x00\x41\x63\x36\x1C\x08\x00\x00',
    '?':  b'\x02\x03\x51\x59\x0F\x06\x00\x00',
    '@':  b'\x3E\x7F\x41\x5D\x5D\x1F\x1E\x00',
    'A':  b'\x7C\x7E\x13\x13\x7E\x7C\x00\x00',
    'B':  b'\x41\x7F\x7F\x49\x49\x7F\x36\x00',
    'C':  b'\x1C\x3E\x63\x41\x41\x63\x22\x00',
    'D':  b'\x41\x7F\x7F\x41\x63\x3E\x1C\x00',
    'E':  b'\x41\x7F\x7F\x49\x5D\x41\x63\x00',
    'F':  b'\x41\x7F\x7F\x49\x1D\x01\x03\x00',
    'G':  b'\x1C\x3E\x63\x41\x51\x73\x72\x00',
    'H':  b'\x7F\x7F\x08\x08\x7F\x7F\x00\x00',
    'I':  b'\x00\x41\x7F\x7F\x41\x00\x00\x00',
    'J':  b'\x30\x70\x40\x41\x7F\x3F\x01\x00',
    'K':  b'\x41\x7F\x7F\x08\x1C\x77\x63\x00',
    'L':  b'\x41\x7F\x7F\x41\x40\x60\x70\x00',
    'M':  b'\x7F\x7F\x0E\x1C\x0E\x7F\x7F\x00',
    'N':  b'\x7F\x7F\x06\x0C\x18\x7F\x7F\x00',
    'O':  b'\x1C\x3E\x63\x41\x63\x3E\x1C\x00',
    'P':  b'\x41\x7F\x7F\x49\x09\x0F\x06\x00',
    'Q':  b'\x1E\x3F\x21\x71\x7F\x5E\x00\x00',
    'R':  b'\x41\x7F\x7F\x09\x19\x7F\x66\x00',
    'S':  b'\x26\x6F\x4D\x59\x73\x32\x00\x00',
    'T':  b'\x03\x41\x7F\x7F\x41\x03\x00\x00',
    'U':  b'\x7F\x7F\x40\x40\x7F\x7F\x00\x00',
    'V':  b'\x1F\x3F\x60\x60\x3F\x1F\x00\x00',
    'W':  b'\x7F\x7F\x30\x18\x30\x7F\x7F\x00',
    'X':  b'\x43\x67\x3C\x18\x3C\x67\x43\x00',
    'Y':  b'\x07\x4F\x78\x78\x4F\x07\x00\x00',
    'Z':  b'\x47\x63\x71\x59\x4D\x67\x73\x00',
    '[':  b'\x00\x7F\x7F\x41\x41\x00\x00\x00',
    '\\': b'\x01\x03\x06\x0C\x18\x30\x60\x00',
    ']':  b'\x00\x41\x41\x7F\x7F\x00\x00\x00',
    '^':  b'\x08\x0C\x06\x03\x06\x0C\x08\x00',
    '_':  b'\x80\x80\x80\x80\x80\x80\x80\x80',
    '`':  b'\x00\x00\x03\x07\x04\x00\x00\x00',
    'a':  b'\x20\x74\x54\x54\x3C\x78\x40\x00',
    'b':  b'\x41\x7F\x3F\x48\x48\x78\x30\x00',
    'c':  b'\x38\x7C\x44\x44\x6C\x28\x00\x00',
    'd':  b'\x30\x78\x48\x49\x3F\x7F\x40\x00',
    'e':  b'\x38\x7C\x54\x54\x5C\x18\x00\x00',
    'f':  b'\x48\x7E\x7F\x49\x03\x02\x00\x00',
    'g':  b'\x98\xBC\xA4\xA4\xF8\x7C\x04\x00',
    'h':  b'\x41\x7F\x7F\x08\x04\x7C\x78\x00',
    'i':  b'\x00\x44\x7D\x7D\x40\x00\x00\x00',
    'j':  b'\x60\xE0\x80\x80\xFD\x7D\x00\x00',
    'k':  b'\x41\x7F\x7F\x10\x38\x6C\x44\x00',
    'l':  b'\x00\x41\x7F\x7F\x40\x00\x00\x00',
    'm':  b'\x7C\x7C\x18\x38\x1C\x7C\x78\x00',
    'n':  b'\x7C\x7C\x04\x04\x7C\x78\x00\x00',
    'o':  b'\x38\x7C\x44\x44\x7C\x38\x00\x00',
    'p':  b'\x84\xFC\xF8\xA4\x24\x3C\x18\x00',
    'q':  b'\x18\x3C\x24\xA4\xF8\xFC\x84\x00',
    'r':  b'\x44\x7C\x78\x4C\x04\x1C\x18\x00',
    's':  b'\x48\x5C\x54\x54\x74\x24\x00\x00',
    't':  b'\x00\x04\x3E\x7F\x44\x24\x00\x00',
    'u':  b'\x3C\x7C\x40\x40\x3C\x7C\x40\x00',
    'v':  b'\x1C\x3C\x60\x60\x3C\x1C\x00\x00',
    'w':  b'\x3C\x7C\x70\x38\x70\x7C\x3C\x00',
    'x':  b'\x44\x6C\x38\x10\x38\x6C\x44\x00',
    'y':  b'\x9C\xBC\xA0\xA0\xFC\x7C\x00\x00',
    'z':  b'\x4C\x64\x74\x5C\x4C\x64\x00\x00',
    '{':  b'\x08\x08\x3E\x77\x41\x41\x00\x00',
    '|':  b'\x00\x00\x00\x77\x77\x00\x00\x00',
    '}':  b'\x41\x41\x77\x3E\x08\x08\x00\x00',
    '~':  b'\x02\x03\x01\x03\x02\x03\x01\x00',
}

class Ssd1306:
    """Driver for the SSD1306 OLED display."""

    # Define various hardware constants:
    I2C_ADDR    = I2cAddress.addr8(0x78)
    CMD_NOARG   = b'\x80'   # Command/opcode
    CMD_ARG     = b'\x00'   # Command/opcode/arg/arg...
    CMD_PIXEL   = b'\x40'   # Command/data/data/data/...

    def __init__(self, i2c):
        """Link to the designated I2C controller."""
        assert isinstance(i2c, I2cController)
        self.i2c = i2c
        self.page = 0
        self.reset()

    def _cmd(self, dat):
        """Internal shortcut for sending command opcodes."""
        cmd = self.CMD_ARG if len(dat) > 1 else self.CMD_NOARG
        return self.i2c.write(self.I2C_ADDR, dat, cmd)

    def _dat(self, chr):
        """Internal shortcut for sending an 8x8 pixel block."""
        dat = SSD1306_FONT.get(chr, SSD1306_SPACE)
        return self.i2c.write(self.I2C_ADDR, dat, self.CMD_PIXEL)

    def reset(self):
        """Reset display and set initial configuration."""
        ok = True                           # Abort early on error
        self.page = 0                       # Reset software state
        ok = ok and self._cmd(b'\xAE')      # Display OFF
        ok = ok and self._cmd(b'\xD5\x80')  # Clock divide = Default
        ok = ok and self._cmd(b'\xA8\x1F')  # Multiplexing = 32 rows
        ok = ok and self._cmd(b'\xD3\x00')  # No display offset
        ok = ok and self._cmd(b'\x40')      # Start line = 0
        ok = ok and self._cmd(b'\x8D\x14')  # Charge pump
        ok = ok and self._cmd(b'\x20\x00')  # Memory mode = Horizontal
        ok = ok and self._cmd(b'\xA1')      # Horizontal mirroring
        ok = ok and self._cmd(b'\xC8')      # Vertical mirroring
        ok = ok and self._cmd(b'\xDA\x02')  # COM pin configuration
        ok = ok and self._cmd(b'\x81\x8F')  # Contrast
        ok = ok and self._cmd(b'\xD9\xF1')  # Precharge period
        ok = ok and self._cmd(b'\xDB\x40')  # VCOMH threshold
        ok = ok and self._cmd(b'\xA4')      # Normal readout mode
        ok = ok and self._cmd(b'\xA6')      # Non-inverted display
        ok = ok and self._cmd(b'\xAF')      # Display ON
        return ok

    def display(self, text):
        """Display a message string."""
        ok = True
        # Set the write pointer:
        ok = ok and self._cmd(bytes([0x21, 0, 127]))
        ok = ok and self._cmd(bytes([0x22, self.page, self.page+3]))
        # Draw each character to the display buffer.
        # (128 x 32 pixels = 16 x 4 characters)
        for n in range(64):
            ok = ok and self._dat(text[n] if n < len(text) else ' ')
        # Swap display to the new page.
        ok = ok and self._cmd(bytes([0x40 | 8*self.page]))
        if ok: self.page = 4 - self.page
        return ok
