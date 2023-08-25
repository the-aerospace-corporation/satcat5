//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/net_core.h>
#include <satcat5/ptp_tracking.h>

namespace log = satcat5::log;
using satcat5::ptp::NSEC_PER_SEC;
using satcat5::ptp::SUBNS_PER_MSEC;
using satcat5::ptp::Time;
using satcat5::ptp::TrackingClock;
using satcat5::ptp::TrackingClockDebug;
using satcat5::ptp::TrackingCoeff;
using satcat5::ptp::TrackingController;
using satcat5::ptp::TrackingDither;
using satcat5::util::abs_s64;
using satcat5::util::divide;
using satcat5::util::modulo;

// Enable additional diagnostics? (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

// Enable dither of TrackingController output?
#ifndef SATCAT5_PTRK_DITHER
#define SATCAT5_PTRK_DITHER 1
#endif

// We need signed accumulators, but the "UintWide" is unsigned only.
// Create some helper functions to help with two's-complement conversion.
inline bool wide_lt_zero(const TrackingController::Accumulator& x) {
    return x.m_data[x.width_words()-1] >= 0x80000000u;
}

inline s64 wide_to_output(const TrackingController::Accumulator& x) {
    return s64(x >> TrackingCoeff::SCALE);
}

Time TrackingClockDebug::clock_adjust(const Time& amount)
{
    return m_target->clock_adjust(amount);
}

void TrackingClockDebug::clock_rate(s64 offset)
{
    m_rate = offset; m_target->clock_rate(offset);
}

TrackingDither::TrackingDither(TrackingClock* clk)
    : m_clk(clk)
    , m_disparity(0)
    , m_offset(0)
{
    timer_every(1);
}

Time TrackingDither::clock_adjust(const Time& amount)
{
    // Coarse adjustments are a direct passthrough.
    return m_clk->clock_adjust(amount);
}

void TrackingDither::clock_rate(s64 offset)
{
    // Update target and immediately regenerate dither.
    m_offset = offset;
    timer_event();
}

void TrackingDither::timer_event()
{
    // Add running disparity to the requested output.
    s64 div = divide(m_offset + m_disparity, (s64)65536);
    s64 rem = modulo(m_offset + m_disparity, (s64)65536);
    // Update output and running disparity.
    m_clk->clock_rate(div);
    m_disparity = (u16)rem;
}

TrackingController::TrackingController(
    TrackingClock* clk, const TrackingCoeff& coeff)
    : m_clk(clk)
    , m_coeff(coeff)
    , m_debug(0)
    , m_last_rcvd(0)
    , m_prng()
    , m_accum(u32(0))
{
    reconfigure(coeff);
    reset();
}

void TrackingController::reconfigure(const TrackingCoeff& coeff)
{
    m_coeff = coeff;
    if (DEBUG_VERBOSE > 0) {
        auto level = coeff.ok() ? log::DEBUG : log::ERROR;
        log::Log(level, "PTP-Track: Config")
            .write10((s32)m_coeff.kp)
            .write10((s32)m_coeff.ki)
            .write10((s32)m_coeff.ymax);
    } else if (!coeff.ok()) {
        log::Log(log::ERROR, "PTP-Track: Bad config.");
    }
}


void TrackingController::reset()
{
    // Reset oscillator control signal.
    m_clk->clock_rate(0);
    // Reset accumulator state.
    m_accum = 0;
}

void TrackingController::update(const Time& rxtime, const Time& delta)
{
    constexpr Time MAX_FINE(2000 * SUBNS_PER_MSEC);
    constexpr Time MAX_ELAPSED(1000 * SUBNS_PER_MSEC);

    // Calculate time since the last received message.
    Time elapsed = (rxtime - m_last_rcvd).abs();
    if (elapsed > MAX_ELAPSED) elapsed = MAX_ELAPSED;
    m_last_rcvd = rxtime;

    // Attempt a coarse adjustment?
    Time filter_input = delta;
    if (delta.abs() > MAX_FINE) {
        log::Log(log::INFO, "PTP-Track: Coarse update")
            .write10((s32)delta.secs())
            .write10((u32)delta.nsec());
        reset();
        filter_input = m_clk->clock_adjust(delta);
        m_last_rcvd += delta;
    }

    // Linear tracking-loop update.
    filter((u32)elapsed.delta_nsec(), filter_input.delta_subns());
}

void TrackingController::filter(u32 elapsed_nsec, s64 delta_subns)
{
    // Sanity check on the input to prevent overflow.
    constexpr u64 MAX_DELTA = u64(100 * SUBNS_PER_MSEC);
    u64 delta_abs = abs_s64(delta_subns);
    if (delta_abs > MAX_DELTA) delta_abs = MAX_DELTA;

    // Convert inputs to extra-wide integers for more dynamic range,
    // then multiply by the KI and KP loop-gain coefficients.
    // Note: Our bigint only handles unsigned, so some care is required.
    Accumulator delta_i(delta_abs);
    Accumulator delta_p(delta_abs);
    delta_i *= Accumulator(m_coeff.ki);
    delta_p *= Accumulator(m_coeff.kp);

    // Compensate for changes to the effective sample interval T0, using
    // most recent elapsed time as a proxy for future sample intervals.
    //  * Output to NCO is a rate, held and accumulated for T0 seconds.
    //    Therefore, outputs must be scaled by 1/T0 to compensate.
    //  * I gain is missing implicit T0^2, so net scaling by T0.
    //  * P gain is missing implicit T0, so net scaling is unity.
    delta_i *= Accumulator(elapsed_nsec);
    delta_p *= Accumulator(NSEC_PER_SEC);

    // Done with multiplication, so we can restore the original sign.
    if (delta_subns < 0) {
        delta_i = -delta_i;
        delta_p = -delta_p;
    }

    // Update the accumulator.
    m_accum += delta_i;

    // Clamp accumulator term to +/- ymax, to mitigate windup.
    Accumulator clamp_pos(m_coeff.ymax);
    clamp_pos <<= TrackingCoeff::SCALE;
    Accumulator clamp_neg(-clamp_pos);
    if (wide_lt_zero(m_accum)) {
        // Accumulator is negative -> Compare to the negative limit.
        if (m_accum < clamp_neg) m_accum = clamp_neg;
    } else {
        // Accumulator is positive -> Compare to the positive limit.
        if (m_accum > clamp_pos) m_accum = clamp_pos;
    }

    // Generate dither at the required scale.
    Accumulator dither(SATCAT5_PTRK_DITHER ? m_prng.next() : 0);
    if (m_coeff.SCALE > 32) {
        dither <<= (m_coeff.SCALE - 32);
    } else {
        dither >>= (32 - m_coeff.SCALE);
    }

    // Output is the sum of all filter terms.
    s64 filter_out = wide_to_output(m_accum + delta_p + dither);
    m_clk->clock_rate(filter_out);

    // Optional diagnostics to the log or direct-to-network.
    if (m_debug) {
        auto dst = m_debug->open_write(24);
        if (dst) {
            dst->write_s64(delta_subns);
            dst->write_s64(wide_to_output(m_accum));
            dst->write_s64(filter_out);
            dst->write_finalize();
        }
    }

    if (DEBUG_VERBOSE > 1) {
        log::Log(log::DEBUG, "PTP-Track: Update")
            .write("\n  delta  ").write((u64)delta_subns)
            .write("\n  elapsed").write((u64)elapsed_nsec)
            .write("\n  accum  ").write((u64)wide_to_output(m_accum))
            .write("\n  output ").write((u64)filter_out);
    } else if (DEBUG_VERBOSE > 0) {
        log::Log(log::DEBUG, "PTP-Track: Update")
            .write10((s32)delta_subns)
            .write10((s32)filter_out);
    }
}
