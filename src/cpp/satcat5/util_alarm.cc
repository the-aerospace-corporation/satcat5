//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/polling.h>
#include <satcat5/util_alarm.h>

using satcat5::util::Alarm;

Alarm::Alarm()
    : m_tref(SATCAT5_CLOCK->now())
    , m_alarms(0)
    , m_sticky(0)
    , m_value(0)
    , m_max_time{}
    , m_max_value{}
    , m_exceeded{}
{
    // Nothing else to initialize.
}

void Alarm::limit_clear() {
    m_tref = SATCAT5_CLOCK->now();
    m_alarms = 0;
}

bool Alarm::limit_add(u32 duration, u32 value) {
    // Is there room for another threshold?
    if (m_alarms >= SATCAT5_MAX_ALARMS) return false;

    // If so, save the new alarm parameters.
    m_max_time[m_alarms]    = duration;
    m_max_value[m_alarms]   = value;
    m_exceeded[m_alarms]    = 0;
    ++m_alarms;
    return true;
}

bool Alarm::push_next(u32 value) {
    // Elapsed time since the last call to this method?
    u32 elapsed = m_tref.increment_msec();

    // Update saved value.
    m_value = value;

    // Compare against each active threshold, incrementing
    // or resetting the associated "exceeded" timer.
    bool alarm = false;
    for (unsigned a = 0 ; a < m_alarms ; ++a) {
        if (value > m_max_value[a]) {
            m_exceeded[a] += elapsed;
            if (m_exceeded[a] >= m_max_time[a]) alarm = true;
        } else {
            m_exceeded[a] = 0;
        }
    }
    if (alarm) m_sticky = 1;
    return alarm;
}
