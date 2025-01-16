//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/net_core.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/utils.h>

namespace log = satcat5::log;
using satcat5::ptp::SUBNS_PER_MSEC;
using satcat5::ptp::SUBNS_PER_USEC;
using satcat5::ptp::USEC_PER_SEC;
using satcat5::ptp::Callback;
using satcat5::ptp::Filter;
using satcat5::ptp::Measurement;
using satcat5::ptp::Source;
using satcat5::ptp::Time;
using satcat5::ptp::TrackingClock;
using satcat5::ptp::TrackingCoarse;
using satcat5::ptp::TrackingController;
using satcat5::ptp::TrackingSimple;
using satcat5::util::divide;
using satcat5::util::min_u32;
using satcat5::util::modulo;

// Enable additional diagnostics? (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

// Enable faster frequency acquisition?
#ifndef SATCAT5_PTRK_FASTACQ
#define SATCAT5_PTRK_FASTACQ 1
#endif

TrackingController::TrackingController(TrackingClock* clk, Source* source)
    : Callback(source)
    , m_clocks(clk)
    , m_tref(SATCAT5_CLOCK->now())
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

void TrackingController::reset(bool linear)
{
    // Reset all attached clock objects.
    clock_rate(0);

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
    m_lock_state = linear ? LockState::LINEAR : LockState::RESET;
    m_tref = SATCAT5_CLOCK->now();
}

void TrackingController::update(const Time& delta)
{
    // Calculate time since the last received message.
    // Use microsecond-resolution timers to support higher message rates.
    u32 elapsed_usec = m_tref.increment_usec();
    elapsed_usec = min_u32(1000000, elapsed_usec);
    m_lock_usec = min_u32(1000000000, m_lock_usec + elapsed_usec);

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
    if (m_lock_state == LockState::LINEAR) {
        // Linear mode skips all coarse-acquisition logic.
    } else if (delta.abs() > ADJ_COARSE) {
        // Large errors may indicate that we've lost lock.
        log::Log(log::INFO, "PTP-Track: Coarse").write_obj(delta);
        if (m_lock_state == LockState::RESET || m_lock_alarm >= 3) {
            // Initial startup or several consecutive alarms.
            reset();
            m_lock_state = LockState::ACQUIRE;
            filter_input = clock_adjust(delta);
        } else if (m_lock_usec >= 1000000) {
            // Once locked, don't reset based on one outlier.
            ++m_lock_alarm;
            return 0;
        }
    } else if (SATCAT5_PTRK_FASTACQ && m_lock_state == LockState::ACQUIRE) {
        // If enabled, keep making coarse phase adjustments after each reset.
        // Cumulative adjustments are used to estimate coarse frequency.
        if (delta.abs() < ADJ_FREQ) {
            filter_input = clock_adjust(delta);
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
    if (result != INT64_MAX) clock_rate(result);

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

Time TrackingController::clock_adjust(const Time& amount)
{
    // Clocks are added first-in-last-out, so final item is the primary.
    Time result(0);
    TrackingClock* item = m_clocks.head();
    while (item) {
        result = item->clock_adjust(amount);
        item = m_clocks.next(item);
    }
    return result;
}

void TrackingController::clock_rate(s64 offset)
{
    TrackingClock* item = m_clocks.head();
    while (item) {
        item->clock_rate(offset);
        item = m_clocks.next(item);
    }
}

static constexpr satcat5::ptp::CoeffPII DEFAULT_TIME_CONSTANT(3.0);

TrackingSimple::TrackingSimple(
    satcat5::ptp::TrackingClock* clk,
    satcat5::ptp::Source* source)
    : TrackingController(clk, source)
    , m_ctrl(DEFAULT_TIME_CONSTANT)
{
    add_filter(&m_ampl);
    add_filter(&m_ctrl);
}

TrackingCoarse::TrackingCoarse(TrackingClock* clk, Source* source)
    : Callback(source)
    , m_clock(clk)
{
    // Nothing else to initialize.
}

void TrackingCoarse::ptp_ready(const satcat5::ptp::Measurement& data)
{
    Time delta = data.offset_from_master();
    if (m_clock) m_clock->clock_adjust(-delta);
}
