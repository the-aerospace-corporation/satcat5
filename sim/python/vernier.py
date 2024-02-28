# -*- coding: utf-8 -*-

# Copyright 2022-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
Simulations of Vernier phase-error detector and phase-locked loop

This tool simulates the operation of various aspects of the Vernier
clock-crossing counter synchronizer.  It includes fixed-point simulations
used to help design the block found in "ptp_counter_sync.vhd".
'''

import numpy as np
import sys
from mmcm_cfg import clkgen_limits, freq_vernier
from numba import jit

@jit(nopython=True)
def sampled_clock(npts, fref, fsamp, offset=0.0, jitter=0.0):
    """
    Sample a reference clock with a given user clock
    Args:
        npts (int)      Length of output vector
        fref (float)    Frequency of reference clock (Hz)
        fsamp (float)   Frequency of reference clock (Hz)
        offset (float)  Time offset of user clock (sec)
        jitter (float)  One-sigma jitter of user clock (sec)
    Returns: (array of bool)
    """
    j = np.random.normal(offset, jitter, npts)  # Offset + Gaussian jitter
    t = np.arange(npts) / fsamp + j             # Time of each sample
    return np.mod(t * fref, 1.0) < 0.5          # Modulo reference clock

@jit(nopython=True)
def count_consecutive(x):
    """
    Given a 0/1 vector, count the number of consecutive matching values.
    e.g., "0,0,0,0,0,1,1,1,1,1" --> "1,2,3,4,5,1,2,3,4,5"
    Args: x (array of bool) Binary input sequence
    Returns: (array of int) Consecutive matches
    """
    y = np.zeros(len(x))
    for n in range(len(x)):
        if n == 1 or x[n] != x[n-1]:
            y[n] = 1
        else:
            y[n] = y[n-1] + 1
    return y

def vernier_diff(fsamp, fref, df, dt, jitter=0.0, alg='ctr', npts=250000):
    """
    Generate sampled Vernier clocks at 10.001 MHz and 9.999 MHz, varying
    the user clock according to specified time and frequency offsets.
    Count the number of differences from the nominal case.
    Args:
        fsamp (float)   User sampling frequency (Hz)
        fref (tuple)    Lower and upper reference frequencies (Hz)
        df (vec-float)  A vector of M frequency offsets (Hz)
        dt (vec-float)  A vector of N time offsets (sec)
        jitter (float)  One-sigma jitter of user clock (sec)
        alg (str)       Detector algorithm ('any', 'net', 'one', 'tot')
        npts (int)      Length of vector to consider
    Returns: (MxN matrix of ints)
    """
    # Generate each nominal reference.
    refa = sampled_clock(npts, fref[0], fsamp)
    refb = sampled_clock(npts, fref[1], fsamp)
    # Count cycles since last change.
    ctra = count_consecutive(refa)
    ctrb = count_consecutive(refb)
    ctr_thresh = 0.25 * fsamp / fref[0]
    # Compare against each time and frequency offset.
    score = np.zeros((len(df), len(dt)))
    for r in range(len(df)):
        for c in range(len(dt)):
            clka = sampled_clock(npts, fref[0], fsamp + df[r], dt[c], jitter)
            clkb = sampled_clock(npts, fref[1], fsamp + df[r], dt[c], jitter)
            if alg == 'any':        # Count cycles where any clock is different
                score[r,c] = np.sum((clka ^ refa) | (clkb ^ refb))
            elif alg == 'tot':      # Count total clock differences each cycle
                score[r,c] = np.sum(clka ^ refa) + np.sum(clkb ^ refb)
            elif alg == 'net':      # Net early vs. late differences
                a1 = np.sum((clka ^ refa) & (clka == np.roll(clka,-1)))
                a2 = np.sum((clka ^ refa) & (clka == np.roll(clka,+1)))
                b1 = np.sum((clkb ^ refb) & (clkb == np.roll(clkb,-1)))
                b2 = np.sum((clkb ^ refb) & (clkb == np.roll(clkb,+1)))
                score[r,c] = (a1 - a2) + (b1 - b2)
            elif alg == 'one':      # Single-clock mode (non-Vernier)
                a1 = np.sum((clka ^ refa) & (clka == np.roll(clka,-1)))
                a2 = np.sum((clka ^ refa) & (clka == np.roll(clka,+1)))
                score[r,c] = (a1 - a2)
            elif alg == 'ctr':     # Count cycles since last change
                a1 = np.sum((clka ^ refa) & (ctra > ctr_thresh))
                a2 = np.sum((clka ^ refa) & (ctra < ctr_thresh))
                b1 = np.sum((clkb ^ refb) & (ctrb > ctr_thresh))
                b2 = np.sum((clkb ^ refb) & (ctrb < ctr_thresh))
                score[r,c] = (a1 - a2) + (b1 - b2)
            else:
                raise ValueError('No such algorithm: ' + alg)
    return score

@jit(nopython=True)
def vernier_sync(npts, fsamp, fref, df, dt,
    jitter=0.0, pha_lsb=None, tau_lsb=None, tau_sec=0.004):
    """
    Fixed-point simulation of a VERDACT synchronized counter, comparing the
    synthesized clock pair against the received signal to update estimated
    synchronizer state at each increment.
    Args:
        npts (int)      Length of simulation (samples)
        fsamp (float)   Nominal user sampling frequency (Hz)
        fref (tuple)    Lower and upper reference frequencies (Hz)
        df (float)      Initial frequency offset (Hz)
        dt (float)      Initial phase offset (sec)
        jitter (float)  One-sigma jitter of user clock (sec)
        pha_lsb (int)   Bits per nanosecond, phase accumulator (None = auto)
        tau_lsb (int)   Bits per nanosecond, period accumulator (None = auto)
        tau_sec (float) Filter time-constant (sec)
    Returns: Tuple containing:
        (vec-float)     Estimated REFA clock-phase at each timestep (sec)
        (vec-float)     Error from actual clock-phase (sec)
        (vec-float)     PED output at each timestep (arb)
        (vec-float)     Estimated period at each timestep (sec)
    """
    # Generate the received clock signals.
    # (No real-time adjustments to the clock, just the estimates.)
    refa = sampled_clock(npts, fref[0], fsamp + df, dt, jitter)
    refb = sampled_clock(npts, fref[1], fsamp + df, dt, jitter)
    # Count cycles since last change.
    ctra = count_consecutive(refa)
    ctrb = count_consecutive(refb)
    ctr_thresh = 0.25 * fsamp / fref[0]
    # Effective VPED gain is estimated empirically.
    # TODO: There seems to be a small variation with fsamp.
    ped_gain = 128
    # Set synchronizer loop-gain parameters.
    # Reference: Stephens & Thomas 1995, "Controlled-root formulation for digital
    # phase-locked loops." https://ieeexplore.ieee.org/abstract/document/366295/
    trk_dmpsq = 0.50                    # Damping factor squared
    trk_dmod  = 0.25 / trk_dmpsq        # Modified damping factor
    trk_alpha = 4.0 / (np.pi*tau_sec*fsamp) / (1.0 + trk_dmod)
    trk_beta  = trk_dmod * trk_alpha * trk_alpha
    # Autodetect required scaling?
    auto_bits = lambda x: max(16, round(np.log2(64 / x)))
    if pha_lsb is None: pha_lsb = auto_bits(ped_gain * trk_alpha)
    if tau_lsb is None: tau_lsb = auto_bits(ped_gain * trk_beta)
    # Final fixed-point coefficients.
    pha_scale = (1e9 * 2**pha_lsb)      # Each phase LSB is (1/scale) seconds
    tau_scale = (1e9 * 2**tau_lsb)      # Each period LSB is (1/scale) seconds
    gain_acc = int(ped_gain * trk_alpha * 2**pha_lsb) # Gain for phase accumulator
    gain_tau = int(ped_gain * trk_beta * 2**tau_lsb)  # Gain for period accumulator
    tau_0 = int(tau_scale / fsamp)      # Initial period estimate
    if gain_acc == 0 or gain_tau == 0:
        raise ValueError('Gain rounded to zero!')
    # Set synchronizer initial state.
    # There are separate phase accumulators for CLKA and CLKB, but they
    # share a common estimate of the user-clock period (tau).
    phase_a = 0
    phase_b = 0
    tau_u = tau_0                       # Estimated user-clock period
    tau_s = 0                           # Sub-LSB accumulator for tau_u
    tau_a = int(pha_scale / fref[0])    # Period of RefA
    tau_b = int(pha_scale / fref[1])    # Period of RefB
    sc_ratio = int(tau_scale / pha_scale)
    # Ratiometric accumulator maintains exact ratio between RefA and RefB.
    # (Otherwise we will accumulate sub-LSB offsets over time and lose lock.)
    ratio_accum = 0
    # Simulate each timestep.
    out_pll = np.zeros(npts)
    out_ped = np.zeros(npts)
    out_tau = np.zeros(npts)
    out_rac = np.zeros(npts)
    for t in range(npts):
        # Calculate phase error from latest VPED state.
        clka = (2*phase_a < tau_a)
        clkb = (2*phase_b < tau_b)
        if clka == refa[t]:         erra = 0
        elif ctra[t] < ctr_thresh:  erra = +1
        else:                       erra = -1
        if clkb == refb[t]:         errb = 0
        elif ctrb[t] < ctr_thresh:  errb = +1
        else:                       errb = -1
        # Note the outputs for this cycle.
        out_ped[t] = erra + errb
        out_pll[t] = phase_a / pha_scale
        out_tau[t] = tau_u / tau_scale
        out_rac[t] = ratio_accum
        # Sub-LSB user clock accumulator.
        pincr = (tau_s + tau_u) // sc_ratio
        tau_s = (tau_s + tau_u)  % sc_ratio
        tau_a2 = tau_a + (ratio_accum < 0)
        tau_b2 = tau_b + (ratio_accum >= 0)
        # Update loop-filter state, including ratiometric accumulator.
        phase_a = (phase_a + pincr + gain_acc*(erra+errb)) % tau_a2
        phase_b = (phase_b + pincr + gain_acc*(erra+errb)) % tau_b2
        tau_u = tau_u + gain_tau * (erra + errb)
        # Ratiometric accumulator.  Hard caps help mitigate windup effects.
        ratio_accum = max(-15, min(15, ratio_accum + erra - errb))
        # Sanity check on loop stability.
        if (10*tau_u < 8*tau_0) or (10*tau_u > 12*tau_0):
            raise ValueError('Tau unstable!')
    # Compare output phase to the reference.
    t0 = 1 / fref[0]
    out_ref = np.mod(np.arange(npts) / (fsamp + df) + dt, t0)
    out_dif = np.mod(out_pll - out_ref + t0/2, t0) - t0/2
    # Return the estimated phase, actual phase, and PED output.
    return (out_pll, out_dif, out_ped, out_tau, out_rac)

def plot_scurves(device, refin, fsamp=125e6, jitter=1e-10, show=True):
    # Import plotting libraries.
    from mpl_toolkits.mplot3d import Axes3D     # Enables 3D-projection
    from matplotlib import cm
    import matplotlib.pyplot as plt
    # Design MMCM parameters for a reference at 20 MHz +/- espilon.
    fref = freq_vernier(device, refin, 20e6)
    # Generate an "S-curve" showing mean response vs. small time offsets.
    sst = np.linspace(-1e-9, +1e-9, 1023)
    ss1 = vernier_diff(fsamp, fref, [0.0], sst)
    ss2 = vernier_diff(fsamp, fref, [0.0], sst, jitter)
    # Plot that response
    fig, ax = plt.subplots()
    ax.plot(sst * 1e9, ss1.transpose(), 'k:')
    ax.plot(sst * 1e9, ss2.transpose(), 'b')
    ax.set_xlabel('Time offset (nsec)')
    ax.set_ylabel('PED magnitude (arb)')
    # Generate an "S-curve" showing mean response vs. larger time offsets.
    lst = np.linspace(-100e-9, +100e-9, 255)
    ls1 = vernier_diff(fsamp, fref, [0.0], lst)
    ls2 = vernier_diff(fsamp, fref, [0.0], lst, jitter)
    # Plot that response
    fig, ax = plt.subplots()
    ax.plot(lst * 1e9, ls1.transpose(), 'k:')
    ax.plot(lst * 1e9, ls2.transpose(), 'b')
    ax.set_xlabel('Time offset (nsec)')
    ax.set_ylabel('PED magnitude (arb)')
    # Generate "S-curve" surface for small time and frequency offsets.
    df = np.linspace(-1e3, +1e3, 9)
    dt = np.linspace(-20e-9, +20e-9, 33)
    z = vernier_diff(fsamp, fref, df, dt, jitter)
    # Plot that response.
    fig, ax = plt.subplots(subplot_kw={"projection": "3d"})
    y, x = np.meshgrid(dt * 1e9, df)
    ax.plot_surface(x, y, z, cmap=cm.coolwarm)
    ax.set_xlabel('Frequency (Hz)')
    ax.set_ylabel('Time offset (nsec)')
    ax.set_zlabel('PED magnitude (arb)')
    # Optionally display all plots.
    if show: plt.show()

def plot_vernier_sync(device, refin, fsamp=125e6, jitter=1e-10, npts=8000000, show=True):
    # Import plotting libraries.
    import matplotlib.pyplot as plt
    # Design MMCM parameters for a reference at 20 MHz +/- espilon.
    fref = freq_vernier(device, refin, 20e6)
    # Simulate VERDACT with a moderate phase step.
    t = np.arange(npts) / fsamp
    (_, step_phase, _, _, _) = vernier_sync(npts, fsamp, fref, 0.0, 5.0e-9, jitter)
    # Simulate VERDACT with a phase and frequency step.
    (_, step_freq, _, _, _) = vernier_sync(npts, fsamp, fref, 1e3, 5.0e-9, jitter)
    # Plot both results.
    fig, ax = plt.subplots()
    ax.plot(t * 1e3, step_phase * 1e9, 'b')
    ax.plot(t * 1e3, step_freq * 1e9, 'r')
    ax.set_xlabel('Time offset (msec)')
    ax.set_ylabel('Phase error (nsec)')
    # Optionally display all plots.
    if show: plt.show()

def print_help():
    """ Print a message explaining command-line options. """
    print('Usage: python %s [cmd] [cmd] ...' % sys.argv[0])
    print('  Where each [cmd] is one of the following:')
    print('  * [any number]: Set reference frequency in MHz.')
    print('  * [device name]: Set device family, see "mmcm_cfg.py".')
    print('  * scurve: Plot S-curves for the Vernier PED.')
    print('  * step: Plot step response of VERDACT')
    print('Example: python %s 25 scurve 200 scurve step' % sys.argv[0])

def is_float(s):
    """ Test if a string can be converted to a valid float. """
    try:
        float(s)
        return True
    except ValueError:
        return False

if __name__ == '__main__':
    # Help message if user doesn't specify any arguments.
    if len(sys.argv) < 2:
        print_help()
        sys.exit(-1)
    # Set default parameters, may be overriden later.
    device = clkgen_limits('7series')
    fsamp = 125e6
    refin = 25e6
    # Parse each command-line argument:
    for cmd in sys.argv[1:]:
        if cmd == 'help':
            print_help()
        elif is_float(cmd):
            refin = 1e6 * float(cmd)
        elif cmd.startswith('fs'):
            fsamp = 1e6 * float(cmd[2:])
        elif clkgen_limits(cmd) is not None:
            limits = clkgen_limits(cmd)
        elif cmd == 'scurve':
            plot_scurves(device, refin, fsamp, show=False)
        elif cmd == 'step':
            plot_vernier_sync(device, refin, fsamp, show=False)
        else:
            print('Unrecognized command: ' + cmd)
    # Display all accumulated output plots.
    import matplotlib.pyplot as plt
    plt.show()
