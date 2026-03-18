//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_throttle.h>
#include <satcat5/polling.h>
#include <satcat5/utils.h>

using satcat5::io::WriteableThrottle;
using satcat5::util::min_unsigned;
using satcat5::util::saturate_add;

WriteableThrottle::WriteableThrottle(
    satcat5::io::Writeable* dst,
    unsigned rate_bps)
    : WriteableRedirect(dst)
    , m_rate_bps(rate_bps)
    , m_tokens(rate_bps / 1024)     // Start with ~8 msec worth of credit
    , m_tref(SATCAT5_CLOCK->now())  // Set initial reference time
{
    timer_every(100);
}

unsigned WriteableThrottle::get_write_space() const {
    // Limit transmission based on time since the last packet.
    // Note: Cannot use increment_usec() here due to "const" requirement.
    unsigned limit1 = calc_tokens(m_tref.elapsed_usec());
    unsigned limit2 = WriteableRedirect::get_write_space();
    return min_unsigned(limit1, limit2);
}

bool WriteableThrottle::write_finalize() {
    // Reset flow-control state after each successful packet.
    bool ok = WriteableRedirect::write_finalize();
    if (ok) {
        m_tokens = 0;
        m_tref = SATCAT5_CLOCK->now();
    }
    return ok;
}

unsigned WriteableThrottle::calc_tokens(unsigned usec) const {
    // Calculate increment in bytes from elapsed time in microseconds.
    u64 incr_bytes = (u64(usec) * u64(m_rate_bps)) / 8000000;
    return saturate_add(m_tokens, unsigned(incr_bytes));
}

void WriteableThrottle::timer_event() {
    // Increment TimeRef occasionally to prevent rollover.
    m_tokens = calc_tokens(m_tref.increment_usec());
}
