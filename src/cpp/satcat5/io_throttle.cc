//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_throttle.h>
#include <satcat5/polling.h>

using satcat5::io::WriteableThrottle;

WriteableThrottle::WriteableThrottle(
    satcat5::io::Writeable* dst,
    unsigned rate_bps)
    : WriteableRedirect(dst)
    , m_rate_bps(rate_bps)
    , m_tref(SATCAT5_CLOCK->now())
{
    // Nothing else to initialize.
}

unsigned WriteableThrottle::get_write_space() const {
    // Limit transmission based on time since the last packet.
    unsigned elapsed_usec = m_tref.elapsed_usec();
    u64 limit1 = (u64(elapsed_usec) * u64(m_rate_bps)) / 8000000;
    u64 limit2 = WriteableRedirect::get_write_space();
    return unsigned(limit1 < limit2 ? limit1 : limit2);
}

bool WriteableThrottle::write_finalize() {
    // Update reference timetstamp after each successful packet.
    bool ok = WriteableRedirect::write_finalize();
    if (ok) m_tref = SATCAT5_CLOCK->now();
    return ok;
}
