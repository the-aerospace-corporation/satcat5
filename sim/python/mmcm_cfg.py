# -*- coding: utf-8 -*-

# Copyright 2022-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
Design tool for Vernier clock generators

This tool finds good clock-generator parameters for creating closely-
spaced "Vernier" clocks just above and below 20 MHz.  The supported
device families are:
    Xilinx 7-series ('7series')
    Xilinx Ultrascale ('ultrascale')
    Xilinx Ultrascale+ ('ultraplus')

In general, it is best to use a separate MMCM for this purpose.
This allows generation of tones just above and just below the nominal
frequency, which helps to avoid linearity problems when one output is
a multiple or quasi-multiple of the clock being measured.

See also: ptp_counter_sync.vhd
See also: vernier.py
'''

import numpy as np

# Min and max parameters for different platforms.
def clkgen_limits(family):
    """
    Return clock-generator parameter limits for the specified product
    family, which should be one of the following:
        7series     Xilinx 7-series (all speed grades)
        ultrascale  Xilinx Ultrascale (all speed grades)
    Returns a dictionary on success, None otherwise.
    """
    if family == '7series':
        # Reference: DS181, UG472
        return {
            'vco_min':  600.0e6,
            'vco_max':  1200.0e6,
            'm_range':  np.arange(2.000, 64.125, 0.125),
            'd0_range': np.arange(2.000, 128.125, 0.125),
            'd1_range': np.arange(1, 129),
        }
    elif family == 'ultrascale':
        # Reference: DS892, UG572
        return {
            'vco_min':  600.0e6,
            'vco_max':  1200.0e6,
            'm_range':  np.arange(2.000, 64.125, 0.125),
            'd0_range': np.arange(2.000, 128.125, 0.125),
            'd1_range': np.arange(1, 129),
        }
    elif family == 'ultraplus':
        # Reference: DS922, UG572
        return {
            'vco_min':  800.0e6,
            'vco_max':  1600.0e6,
            'm_range':  np.arange(2.000, 64.125, 0.125),
            'd0_range': np.arange(2.000, 128.125, 0.125),
            'd1_range': np.arange(1, 129),
        }
    else:
        # Not a recognized part family.
        return None

# Maximum DDMTD frequency for initial startup transients.
DDMTD_TOL   = 100e3

def clkgen_check(best, refin, refout, m, d0, d1):
    """ Helper function for clkgen_vernier() to check a single configuration """
    f0 = refin * m / d0
    f1 = refin * m / d1
    # Set maximum tolerable difference for DDMTD.
    if abs(f0 - f1) > DDMTD_TOL: return best
    # Set minimum tolerable difference to avoid exact multiples.
    if abs(f0 - refout) < 1e3: return best
    if abs(f1 - refout) < 1e3: return best
    # Primary figure-of-merit is the least common multiple of the periods.
    score = np.lcm(int(8*d0), int(8*d1)) / (refin * m)
    if score > best[3]:
        return (m, d0, d1, score)
    else:
        return best

def clkgen_vernier(limits, refin, refout):
    """
    Given reference input, find Vernier parameters using a single
    clock-synthesis primitive on the target device family.
    
    The goals are as follows:
        * Generate an output frequency just above REFOUT.
        * Generate an output frequency just below REFOUT.
        * Maximize LCM of the two output clock intervals.
        * Multiplier, divider, and VCO parameters legal for Artix7, speed grade 1.
    Args:
        limits  Parameter limits, see "clkgen_limits".
        refin   Reference input frequency, in Hz
        refout  Reference output frequency, in Hz
    Returns: Tuple with M, D0, D1
    """
    if limits is None: raise Exception('Invalid device limits.')
    # Guess and check over many configurations...
    best = (0, 0, 0, 0)
    for m in limits['m_range']:
        # For each legal VCO frequency...
        vco = refin * m
        if vco < limits['vco_min']: continue
        if vco > limits['vco_max']: continue
        # Find all divisors that are within range of the target frequency.
        d0_range = [d for d in limits['d0_range'] if abs(vco/d - refout) < DDMTD_TOL]
        d1_range = [d for d in limits['d1_range'] if abs(vco/d - refout) < DDMTD_TOL]
        # Try all permutations to find the longest LCM.
        for d0 in d0_range:
            for d1 in d1_range:
                best = clkgen_check(best, refin, refout, m, d0, d1)
    # Print best configuration.
    clkgen_print("Best configuration", refin, best[0:3])
    return (best[0], best[1], best[2])

def clkgen_print(label, refin, cfg):
    """
    Given clock-generator parameters, print a human-readable description.
    Args:
        label   Label to be printed.
        refin   Reference input frequency, in Hz
        cfg     Configuration tuple with M, D0, D1
    """
    # Split the configuration tuple and calculate outputs.
    (m, d0, d1) = cfg
    if d0 <= 0 or d1 <= 0:
        print("%s: No solution." % label)
        return
    refin_mhz = refin / 1e6
    refout0 = refin_mhz * m / d0
    refout1 = refin_mhz * m / d1
    # Calculate the LCM of the two outputs.
    # (Includes the effect of the extra divide-by-two.)
    lcm_ratio = 2 * np.lcm(int(8*d0), int(8*d1)) / (64*m)
    lcm_usec = 1e6 * lcm_ratio / refin
    # Pretty print:
    print("%s: %.3f -> %.3f usec: %.3f, %.3f MHz: %.3f, %.3f, %d" % (
        label, refin_mhz,               # Reference input (MHz)
        lcm_usec,                       # Vernier period (usec)
        min(refout0, refout1),          # Slower output (MHz)
        max(refout0, refout1),          # Faster output (MHz)
        m, d0, d1)                      # Detailed clkgen parameters
    )

def freq_vernier(limits, refin, refout):
    """
    Given reference input, return the upper and lower output frequencies.
    (Calls "clkgen_vernier" and automatically applies returned parameters.)
    Args:
        limits  Device parameters from "clkgen_limits"
        refin   Reference input frequency, in Hz
        refout  Reference output frequency, in Hz
    Returns: Tuple with F_lower and F_upper in Hz
    """
    # Calculate optical clock-generator parameters.
    (m, d1, d2) = clkgen_vernier(limits, refin, refout)
    # Calculate the two output frequencies.
    # (Extra 0.5 is for local divide-by-two used in the sampling circuit.)
    f1 = 0.5 * refin * m / max(d1, d2)  # Lower freq
    f2 = 0.5 * refin * m / min(d1, d2)  # Upper freq
    n1 = int(8 * max(d1, d2))           # Integer divider for F1
    n2 = int(8 * min(d1, d2))           # Integer divider for F2
    return (f1, f2, n1, n2)

if __name__ == '__main__':
    for device in ['7series', 'ultrascale', 'ultraplus']:
        limits = clkgen_limits(device)
        print('Device family: ' + device)
        clkgen_vernier(limits,  20.00e6, 20e6)
        clkgen_vernier(limits,  25.00e6, 20e6)
        clkgen_vernier(limits,  50.00e6, 20e6)
        clkgen_vernier(limits, 100.00e6, 20e6)
        clkgen_vernier(limits, 125.00e6, 20e6)
        clkgen_vernier(limits, 156.25e6, 20e6)
        clkgen_vernier(limits, 200.00e6, 20e6)
