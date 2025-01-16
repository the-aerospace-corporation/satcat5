//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/timeref.h>
#include <satcat5/utils.h>

using satcat5::util::TimeRef;
using satcat5::util::TimeRegister;
using satcat5::util::TimeVal;

// Fixed point scaling: (X * Y) / 2^32
static constexpr unsigned fp_floor(u32 t, u64 k)
    { return unsigned((u64(t) * k) >> 32); }
static constexpr u32 fp_round(unsigned t, u64 k)
    { return u32((u64(t) * k + (1u << 31)) >> 32); }

unsigned TimeVal::elapsed_tick() const {
    // Note: U32 arithmetic handles wraparound correctly,
    // as long as elapsed time is less than UINT32_MAX ticks.
    return unsigned(clk->raw() - tval);
}

unsigned TimeVal::elapsed_usec() const {
    return fp_floor(clk->raw() - tval, clk->m_usec_per_tick);
}

unsigned TimeVal::elapsed_msec() const {
    return fp_floor(clk->raw() - tval, clk->m_msec_per_tick);
}

unsigned TimeVal::increment_usec() {
    unsigned usec = elapsed_usec();
    tval += fp_round(usec, clk->m_tick_per_usec);
    return usec;
}

unsigned TimeVal::increment_msec() {
    unsigned msec = elapsed_msec();
    tval += fp_round(msec, clk->m_tick_per_msec);
    return msec;
}

bool TimeVal::interval_tick(u32 ticks) {
    u32 elapsed = clk->raw() - tval;
    if (elapsed >= ticks) {
        tval += ticks;
        return true;
    } else {
        return false;
    }
}

bool TimeVal::interval_usec(unsigned usec) {
    u32 ticks = fp_round(usec, clk->m_tick_per_usec);
    return interval_tick(ticks);
}

bool TimeVal::interval_msec(unsigned msec) {
    u32 ticks = fp_round(msec, clk->m_tick_per_msec);
    return interval_tick(ticks);
}

TimeVal TimeRef::now() {
    return TimeVal {this, this->raw()};
}

TimeVal TimeRef::checkpoint_usec(unsigned usec) {
    return TimeVal {this, raw() + fp_round(usec, m_tick_per_usec)};
}

TimeVal TimeRef::checkpoint_msec(unsigned msec) {
    return TimeVal {this, raw() + fp_round(msec, m_tick_per_msec)};
}

bool TimeVal::checkpoint_elapsed() {
    // Is the checkpoint enabled?  Measure elapsed time.
    if (!tval) return false;    // Disabled
    u32 elapsed = clk->raw() - tval;

    // Once now() exceeds tval, elapsed time will be a small positive number.
    // Until then, it will be very large due to uint32_t wraparound.
    static const u32 THRESHOLD = UINT32_MAX / 8;
    if (elapsed < THRESHOLD) {
        tval = 0;               // Disable countdown (one-time use)
        return true;            // Interval elapsed
    } else {
        return false;           // Still pending
    }
}

void TimeRef::busywait_usec(unsigned usec) {
    // Note: If m_ticks_per_sec is small, interval may truncate to zero.
    u32 tstart   = raw();
    u32 interval = fp_round(usec, m_tick_per_usec);
    while (raw() - tstart < interval) {}
}

u32 TimeRegister::raw() {
    return *m_reg;
}
