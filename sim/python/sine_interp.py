# -*- coding: utf-8 -*-

# Copyright 2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
Design tool for sine/cosine lookup tables

This tool is a design aide that simulates sine/cosine lookup tables,
including interpolation systems based on estimated derivatives.  It
is primarily used as a design aide in choosing table parameters to
meet specific performance objectives.

See also: sine_interp.vhd
See also: sine_table.vhd
'''

import numpy as np

class LookupTable:
    """Simulate a quantized sine/cosine lookup table."""
    def __init__(self, nbits_angle, nbits_out):
        """Create lookup table:
            nbits_angle:    Bits in the unsigned angle value.
            nbits_out:      Bits in the signed output value.
        """
        self.label = f'Lookup table: {nbits_angle}, {nbits_out}'
        self.step_rad = 2.0 * np.pi / 2**nbits_angle
        self.step_out = 2.0 / 2**nbits_out

    def angle(self, theta):
        """Round angle to nearest step."""
        return self.step_rad * np.round(theta / self.step_rad)

    def output(self, value):
        """Round output to nearest step."""
        return self.step_out * np.round(value / self.step_out)

    def cos_sin(self, theta):
        """Lookup-table cosine + sine."""
        x = self.output(np.cos(self.angle(theta)))
        y = self.output(np.sin(self.angle(theta)))
        return (x, y)

class Interpolator:
    """Simulate an interpolator with quantized lookup tables."""
    def __init__(self, nbits_angle, nbits_table, nbits_out):
        """Create interpolator object:
            nbits_angle:    Bits in the unsigned angle value.
            nbits_table:    Bits in intermediate lookup table.
            nbits_out:      Bits in the final signed output value.
        """
        self.label = f'Interpolator: {nbits_angle}, {nbits_table}, {nbits_out}'
        self.table = LookupTable(nbits_angle, nbits_table)
        self.step_out = 2.0 / 2**nbits_out

    def output(self, value):
        """Round output to nearest step."""
        return self.step_out * np.round(value / self.step_out)

    def cos_sin(self, theta):
        """Interpolated cosine + sine."""
        delta   = theta - self.table.angle(theta)
        (x1,y1) = self.table.cos_sin(theta)
        x2      = self.output(x1 - delta * y1)
        y2      = self.output(y1 + delta * x1)
        return (x2, y2)

def rms_error(obj, ncheck=2**22, verbose=False):
    """Measure RMS error of the designated cos_sin calculator."""
    theta   = np.linspace(0, 2*np.pi, ncheck)
    ref     = np.exp(1j * theta)
    (x,y)   = obj.cos_sin(theta)
    rms     = np.std(x + 1j*y - ref)
    if verbose: print(f'{obj.label}: RMS={rms*1e6:.1f} ppm')
    return rms

if __name__ == '__main__':
    test = [
        LookupTable(10, 18),
        LookupTable(12, 18),
        LookupTable(14, 18),
        LookupTable(16, 18),
        LookupTable(18, 18),
        Interpolator(10, 18, 18),
        Interpolator(12, 18, 18),
        Interpolator(14, 18, 18),
    ]
    for obj in test:
        rms_error(obj, verbose=True)
