//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_timer.h>
#include <satcat5/polling.h>

using satcat5::cfg::Timer;
using satcat5::util::TimeVal;

u32 Timer::raw() {
    return m_ctrl[REGADDR_PERF_CTR];
}

TimeVal Timer::last_event() {
    return TimeVal {this, m_ctrl[REGADDR_LAST_EVT]};
}

void Timer::timer_interval(unsigned usec) {
    m_ctrl[REGADDR_TIMER_LEN] = usec * ticks_per_usec() - 1;
}

void Timer::timer_callback(poll::OnDemand* callback) {
    m_callback = callback;
}

void Timer::wdog_disable() {
    m_ctrl[REGADDR_WDOG] = WDOG_PAUSE;
}

void Timer::wdog_update(u32 usec) {
    m_ctrl[REGADDR_WDOG] = usec * ticks_per_usec();
}

void Timer::irq_event() {
    if (m_callback) m_callback->request_poll();
}
