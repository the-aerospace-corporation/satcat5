//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_test/ptp_clock.h>
#include <satcat5/utils.h>

using satcat5::ptp::SimulatedClock;
using satcat5::ptp::Time;
using satcat5::util::round_s64;
using satcat5::util::round_u64;
using satcat5::util::uint128_t;

SimulatedClock::SimulatedClock(double nominal_hz, double actual_hz)
    : m_scale_nominal(nominal_hz / TICKS_PER_SEC)
    , m_rate_actual(actual_hz)
    , m_nco_rate(round_s64(TICKS_PER_SEC / nominal_hz))
    , m_nco_accum(satcat5::util::UINT128_ZERO)
    , m_count_coarse(0)
    , m_count_fine(0)
    , m_rtc(0)
{
    // Nothing else to initialize.
}

Time SimulatedClock::clock_adjust(const Time& amount) {
    ++m_count_coarse;
    m_rtc += amount;
    return Time(0);
}

void SimulatedClock::clock_rate(s64 offset) {
    ++m_count_fine;
    m_offset = offset;
    m_stats.add(offset);
}

double SimulatedClock::clock_offset_ppm() const {
    return m_offset * ref_scale() * 1e6;
}

double SimulatedClock::ref_scale() const {
    return m_scale_nominal;
}

void SimulatedClock::run(const Time& dt) {
    // Advance the NCO in discrete steps.
    double dt_secs = dt.delta_subns() / double(satcat5::ptp::SUBNS_PER_SEC);
    u64 num_clocks = round_u64(dt_secs * m_rate_actual);

    // Increment internal counter at full precision.
    const uint128_t incr(num_clocks);
    const uint128_t rate(u64(m_nco_rate + m_offset));
    m_nco_accum += incr * rate;

    // Internal resolution is higher than RTC; retain leftovers.
    const uint128_t scale(TICKS_PER_SUBNS);
    m_rtc += Time(s64(m_nco_accum / scale));
    m_nco_accum = m_nco_accum % scale;
}
