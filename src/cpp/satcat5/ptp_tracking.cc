//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/net_core.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/timer.h>
#include <satcat5/utils.h>

namespace log = satcat5::log;
using satcat5::ptp::SUBNS_PER_MSEC;
using satcat5::ptp::SUBNS_PER_USEC;
using satcat5::ptp::USEC_PER_SEC;
using satcat5::ptp::Callback;
using satcat5::ptp::Filter;
using satcat5::ptp::Measurement;
using satcat5::ptp::Time;
using satcat5::ptp::TrackingClock;
using satcat5::ptp::TrackingController;
using satcat5::ptp::TrackingDither;
using satcat5::util::divide;
using satcat5::util::GenericTimer;
using satcat5::util::min_u32;
using satcat5::util::modulo;

// Enable additional diagnostics? (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

// Enable faster frequency acquisition?
#ifndef SATCAT5_PTRK_FASTACQ
#define SATCAT5_PTRK_FASTACQ 1
#endif

TrackingDither::TrackingDither(TrackingClock* clk)
    : m_clk(clk)
    , m_disparity(0)
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
    GenericTimer* timer, TrackingClock* clk, Client* client)
    : Callback(client)
    , m_timer(timer)
    , m_clk(clk)
    , m_tref(timer->now())
    , m_freq_accum(0)
    , m_lock_alarm(0)
    , m_lock_usec(0)
    , m_lock_state(LockState::ACQUIRE)
{
    reset();
}

void TrackingController::ptp_ready(const Measurement& data)
{
    update(-data.offset_from_master());
}

void TrackingController::reset()
{
    // Reset oscillator control signal.
    if (m_clk) m_clk->clock_rate(0);

    // Reset each filter in the chain.
    Filter* filter = m_filters.head();
    while (filter) {
        filter->reset();
        filter = m_filters.next(filter);
    }

    // Reset lock/unlock state.
    m_freq_accum = 0;
    m_lock_alarm = 0;
    m_lock_usec = 0;
    m_lock_state = LockState::RESET;
}

void TrackingController::update(const Time& delta)
{
    // Calculate time since the last received message.
    // Use microsecond-resolution timers to support higher message rates.
    u32 elapsed_usec = min_u32(1000000, m_timer->elapsed_incr(m_tref));
    m_lock_usec = min_u32(1000000000, m_lock_usec + elapsed_usec);

    // Sanity check: Abort immediately if no clock is configured.
    if (!m_clk) return;

    // Apply coarse adjustments if required, then fine tracking.
    s64 input = coarse(delta);
    filter(elapsed_usec, input);
}

s64 TrackingController::coarse(const Time& delta)
{
    constexpr Time ADJ_COARSE(SUBNS_PER_MSEC * 10);
    constexpr Time ADJ_FREQ(SUBNS_PER_USEC * 1000);
    constexpr Time ADJ_FINE(SUBNS_PER_USEC * 10);

    Time filter_input = delta;
    if (delta.abs() > ADJ_COARSE) {
        log::Log(log::INFO, "PTP-Track: Coarse").write_obj(delta);
        if (m_lock_state == LockState::RESET || m_lock_alarm >= 3) {
            // Initial startup or several consecutive alarms.
            reset();
            m_lock_state = LockState::ACQUIRE;
            filter_input = m_clk->clock_adjust(delta);
        } else if (m_lock_usec >= 1000000) {
            // Once locked, don't reset based on one outlier.
            ++m_lock_alarm;
            return 0;
        }
    } else if (SATCAT5_PTRK_FASTACQ && m_lock_state == LockState::ACQUIRE) {
        // If enabled, keep making coarse phase adjustments after each reset.
        // Cumulative adjustments are used to estimate coarse frequency.
        if (delta.abs() < ADJ_FREQ) {
            filter_input = m_clk->clock_adjust(delta);
            m_freq_accum += (delta - filter_input).delta_subns();
        }
        // Wait for at least one second to improve estimation quality.
        // Goal is to get initial state within ~1ppm for faster pull-in.
        if (m_lock_usec >= 1000000) {
            log::Log(log::INFO, "PTP-Track: Adjust")
                .write10(m_freq_accum).write10(m_lock_usec);
            Filter* filter = m_filters.head();
            while (filter) {
                filter->rate(m_freq_accum, m_lock_usec);
                filter = m_filters.next(filter);
            }
            m_lock_state = LockState::TRACK;
        }
    } else if (delta.abs() < ADJ_FINE) {
        // Well-aligned measurements reset the consecutive-alarm counter.
        m_lock_alarm = 0;
        m_lock_state = LockState::TRACK;
    }

    return filter_input.delta_subns();
}

void TrackingController::filter(u32 elapsed_usec, s64 delta_subns)
{
    // Apply each filter in the chain.
    Filter* filter = m_filters.head();
    s64 result = delta_subns;
    while (filter) {
        result = filter->update(result, elapsed_usec);
        filter = m_filters.next(filter);
    }

    // Keep this output sample?
    if (m_clk && result != INT64_MAX)
        m_clk->clock_rate(result);

    // Additinoal diagnostics?
    if (DEBUG_VERBOSE > 1) {
        log::Log(log::DEBUG, "PTP-Track: Update")
            .write("\n  delta  ").write10(delta_subns)
            .write("\n  elapsed").write10(elapsed_usec)
            .write("\n  output ").write10(result);
    } else if (DEBUG_VERBOSE > 0) {
        log::Log(log::DEBUG, "PTP-Track: Update")
            .write10(delta_subns).write10(result);
    }
}
