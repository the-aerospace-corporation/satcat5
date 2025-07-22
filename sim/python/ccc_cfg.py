# -*- coding: utf-8 -*-

# Copyright 2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
Design tool for Vernier clock generators

This tool finds good clock-generator parameters for creating closely-
spaced "Vernier" clocks just above and below 20 MHz on two separate PLLs. It
assumes external feedback mode is selected, integer mode is enabled, and
outputs 0 and 1 (within a single PLL) are identical frequencies. The supported
device families are:
    Microsemi PolarFire SoC ('polarfire')

See also: mmcm_cfg.py
See also: ptp_counter_sync.vhd
See also: vernier.py
'''

import numpy as np

# NOTE: Through experimentation, it was discovered that the vernier counters had trouble
# locking when LCM is too large.  This constant is to limit the candidates.
LCM_MAX = 9e-6   # 9 usec was the LCM value that worked in Xilinx Ultrascale designs

# Min and max parameters for different platforms.
def clkgen_limits(family):
    """
    Return clock-generator parameter limits for the specified product
    family.

    Returns a dictionary on success, None otherwise.
    """
    if family == 'polarfire':
        # Reference: PolarFire SoC Datasheet, PolarFire Family Clocking Resources
        return {
            'vco_min':  800.0e6,
            'vco_max':  5000.0e6,
            'fpfd_min': 1e6,
            'fpfd_max': 312e6,
            'rfdiv_range': np.arange(1, 63+1),
            'fbdiv_range': np.arange(12, 1250+1),
            'outdiv0_range': np.arange(1, 127+1),
        }
    else:
        # Not a recognized part family.
        return None

def clkgen_check(best, refin, refout, cfg0, cfg1, candidates):
    """
    Helper function for clkgen_vernier() to check a single configuration.

    Args:
        best        (f0, f1, score)
        refin       Reference input frequency
        refout      Target output frequency
        cfg0        (f_out, rfdiv, fbdiv, outdiv)
        cfg1        (f_out, rfdiv, fbdiv, outdiv)
        candidates  running list of candidate configurations 
    Returns: Tuple with (cfg0, cfg1, score) and list of candidates 
    """
    f0, rfdiv0, fbdiv0, outdiv0 = cfg0
    f1, rfdiv1, fbdiv1, outdiv1 = cfg1
    # Set maximum tolerable difference for DDMTD.
    if abs(f0 - f1) > ddmtd_tol: return best, candidates
    # Set minimum tolerable difference to avoid exact multiples.
    if abs(f0 - refout) < 1e3: return best, candidates
    if abs(f1 - refout) < 1e3: return best, candidates

    # Primary figure-of-merit is the least common multiple of the periods.
    score = clk_lcm(refin, cfg0, cfg1)
    candidates.append((cfg0, cfg1, score))

    if score > best[2] and score < LCM_MAX:
        return (cfg0, cfg1, score), candidates
    else:
        return best, candidates


def clk_lcm (refin, cfg0, cfg1):
    """
    Helper function to calculate the lcm of two configurations.

    Args:
        refin   Reference input frequency
        cfg0    (f_out, rfdiv, fbdiv, outdiv)
        cfg1    (f_out, rfdiv, fbdiv, outdiv)
    Returns: LCM in seconds 
    """
    f0, rfdiv0, fbdiv0, outdiv0 = cfg0
    f1, rfdiv1, fbdiv1, outdiv1 = cfg1
    numer0 = rfdiv0 * fbdiv1
    numer1 = rfdiv1 * fbdiv0
    numer_lcm = np.lcm(numer0, numer1)

    # (Include the effect of the extra divide-by-two.)
    numer_lcm = 2* numer_lcm
    return (numer_lcm / fbdiv0 /fbdiv1 /refin)


def clkgen_vernier(limits, refin, refout, ddmtd_tol, debug_candidates=False):
    """
    Given reference input, find Vernier frequencies for two separate PLLs. This
    assumes each PLL is in external feedback mode, and has outputs 0 and 1
    enabled at identical frequencies.

    The goals are as follows:
        * Generate an output frequency just above REFOUT.
        * Generate an output frequency just below REFOUT.
        * Maximize LCM of the two output clock intervals.
        * Multiplier, divider, and VCO parameters legal for device.
    Args:
        limits  Parameter limits, see "clkgen_limits".
        refin   Reference input frequency, in Hz
        refout  Reference output frequency, in Hz
    Returns: Tuple with f0, f1
    """
    if limits is None: raise Exception('Invalid device limits.')
    # Guess and check over many configurations...
    while True:
        pll_ratios = set() 
        outs = set()
        cfgs = []
        best = (0, 0, 0) # cfg0, cfg1, score
        candidates = []

        for rfdiv in limits['rfdiv_range']:
            fpfd = refin/rfdiv
            if fpfd > limits['fpfd_max']: continue
            if fpfd < limits['fpfd_min']: continue
            temp = 4*fpfd
            for fbdiv in limits['fbdiv_range']:
                temp2 = temp*fbdiv
                out = fpfd * fbdiv
                pll_ratio = rfdiv/fbdiv

                if abs(out - refout) > ddmtd_tol: continue
                if  pll_ratio in pll_ratios: continue 
                pll_ratios.add(pll_ratio)

                for outdiv0 in limits['outdiv0_range']:
                    vco = temp2*outdiv0
                    if vco > limits['vco_max']: continue
                    if vco < limits['vco_min']: continue
                    if out in outs: continue
                    outs.add(out)
                    cfgs.append((out, rfdiv, fbdiv, outdiv0))

        for i in range(len(outs)):
            for j in range(i+1, len(outs)):
                cfg0 = cfgs[i]
                cfg1 = cfgs[j]
                best, candidates = clkgen_check(best, refin, refout, cfg0, cfg1, candidates)

        if best[0] == 0 or best[1] == 0:
            ddmtd_tol *= 2
        else:
            print("DDMTD tolerance:", ddmtd_tol/1e3, "kHz")
            break

    if debug_candidates == True:
        candidates.sort(key=lambda x: x[2])
        for i in candidates:
            clkgen_print("candidate configuration", refin, refout, i[0], i[1])

    # Print best configuration.
    clkgen_print("Best configuration", refin, refout, best[0], best[1])
    return (best[0], best[1])

def clkgen_print(label, refin, refout, cfg0, cfg1):
    """
    Given clock frequencies, print a human-readable description.
    Args:
        label   Label to be printed.
        refin   Reference input frequency, in Hz
        cfg0    (f_out, rfdiv, fbdiv, outdiv)
        cfg1    (f_out, rfdiv, fbdiv, outdiv)
    """
    # Split the configuration tuple and calculate outputs.
    if cfg0 == 0 or cfg1 == 0:
        print("%s: No solution for %.3f MHz." % (label, refin/1e6))
        return
    f0, rfdiv0, fbdiv0, outdiv0 = cfg0
    f1, rfdiv1, fbdiv1, outdiv1 = cfg1

    refin_mhz = refin / 1e6
    f0_mhz = f0/1e6
    f1_mhz = f1/1e6

    # Calculate the LCM of the two outputs.
    lcm_usec = 1e6 * clk_lcm(refin, cfg0, cfg1)

    # Pretty print:
    print(
        "%s: %.3f -> %.9f usec | %.9f, %.9f MHz | %d, %d, %d | %d, %d, %d" % (
        label, refin_mhz,     # Reference input (MHz)
        lcm_usec,             # Vernier period (usec)
        min(f0_mhz, f1_mhz),          # Slower output (MHz)
        max(f0_mhz, f1_mhz),          # Faster output (MHz)
        rfdiv0, fbdiv0, outdiv0,
        rfdiv1, fbdiv1, outdiv1)
    )

if __name__ == '__main__':
    # Maximum DDMTD frequency for initial startup transients.
    ddmtd_tol   = 800e3
    f_target = 20e6
    for device in ['polarfire']:
        limits = clkgen_limits(device)
        print('Device family: ' + device)
        clkgen_vernier(limits,  20.00e6, f_target, ddmtd_tol)
        clkgen_vernier(limits,  25.00e6, f_target, ddmtd_tol)
        clkgen_vernier(limits,  50.00e6, f_target, ddmtd_tol)
        clkgen_vernier(limits,  54.00e6, f_target, ddmtd_tol)
        clkgen_vernier(limits, 100.00e6, f_target, ddmtd_tol)
        clkgen_vernier(limits, 125.00e6, f_target, ddmtd_tol)
        clkgen_vernier(limits, 156.25e6, f_target, ddmtd_tol)
        clkgen_vernier(limits, 200.00e6, f_target, ddmtd_tol)
