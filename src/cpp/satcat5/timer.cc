//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/timer.h>
#include <satcat5/utils.h>

using satcat5::util::GenericTimer;
using satcat5::util::TimerRegister;

u32 GenericTimer::elapsed_ticks(u32 tref)
{
    // Note: U32 arithmetic handles wraparound correctly,
    // as long as elapsed time is less than UINT_MAX ticks.
    return now() - tref;
}

unsigned GenericTimer::elapsed_usec(u32 tref)
{
    u32 elapsed = now() - tref;
    return (unsigned)(elapsed / m_ticks_per_usec);
}

unsigned GenericTimer::elapsed_incr(u32& tref)
{
    // Note: Divide-then-multiply helps avoid drift in long-running
    //       timers caused by cumulative rounding errors.
    u32 elapsed_usec = (now() - tref) / m_ticks_per_usec;
    u32 elapsed_tick = elapsed_usec * m_ticks_per_usec;
    tref += elapsed_tick;
    return (unsigned)elapsed_usec;
}

unsigned GenericTimer::elapsed_msec(u32& tref)
{
    // Note: Divide-then-multiply helps avoid drift in long-running
    //       timers caused by cumulative rounding errors.
    u32 elapsed_msec = (now() - tref) / m_ticks_per_msec;
    u32 elapsed_tick = elapsed_msec * m_ticks_per_msec;
    tref += elapsed_tick;
    return (unsigned)elapsed_msec;
}

bool GenericTimer::elapsed_test(u32& tref, unsigned usec)
{
    u32 interval = (u32)(usec * m_ticks_per_usec);
    u32 elapsed  = now() - tref;
    if (elapsed >= interval) {
        tref += elapsed;
        return true;
    } else {
        return false;
    }
}

u32 GenericTimer::get_checkpoint(unsigned usec)
{
    return now() + (u32)(usec * m_ticks_per_usec);
}

bool GenericTimer::checkpoint_elapsed(u32& tref)
{
    // Is the checkpoint enabled?  Measure elapsed time.
    if (!tref) return false;    // Disabled
    u32 elapsed = now() - tref;

    // Has elapsed-time rolled over from 0 to UINT_MAX?
    static const u32 THRESHOLD = UINT32_MAX / 2;
    if (elapsed < THRESHOLD) {
        tref = 0;               // Disable countdown (one-time use)
        return true;            // Interval elapsed
    } else {
        return false;           // Still pending
    }
}

void GenericTimer::busywait_usec(unsigned usec)
{
    u32 tstart   = now();
    u32 interval = (u32)(usec * m_ticks_per_usec);
    while (now() - tstart < interval) {}
}

TimerRegister::TimerRegister(volatile u32* reg, u32 clkref_hz)
    : GenericTimer(div_ceil_u32(clkref_hz, 1000000))
    , m_reg(reg)
{
    // Nothing else to initialize
}

u32 TimerRegister::now()
{
    return *m_reg;
}
