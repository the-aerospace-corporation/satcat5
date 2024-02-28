//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_led.h>
#include <satcat5/cfgbus_stats.h>

using satcat5::cfg::LedArray;
using satcat5::cfg::LedActivity;
using satcat5::cfg::LedActivityCtrl;
using satcat5::cfg::LedWave;
using satcat5::cfg::LedWaveCtrl;

// Sinusoidal "breathing" pattern (32 points)
static const u8 SINE_ARRAY[] = {
        0x00, 0x02, 0x09, 0x15, 0x25, 0x38, 0x4E, 0x66,
        0x7F, 0x98, 0xB0, 0xC6, 0xD9, 0xE9, 0xF5, 0xFC,
        0xFF, 0xFC, 0xF5, 0xE9, 0xD9, 0xC6, 0xB0, 0x98,
        0x7F, 0x66, 0x4E, 0x38, 0x25, 0x15, 0x09, 0x02};

LedArray::LedArray(satcat5::cfg::ConfigBus* cfg,
        unsigned devaddr, unsigned count)
    : m_reg(cfg->get_register(devaddr, 0))
    , m_count(count)
{
    // Turn all LEDs off on startup.
    for (unsigned a = 0 ; a < m_count ; ++a)
        m_reg[a] = 0;
}

u8 LedArray::get(unsigned idx)
{
    if (idx < m_count)
        return (u8)m_reg[idx];
    else
        return 0;
}

void LedArray::set(unsigned idx, u8 brt)
{
    if (idx < m_count)
        m_reg[idx] = (u32)brt;
}

LedActivity::LedActivity(satcat5::cfg::ConfigBus* cfg,
        unsigned devaddr, unsigned regaddr, unsigned stats_idx, u8 brt)
    : m_reg(cfg->get_register(devaddr, regaddr))
    , m_stats_idx(stats_idx)
    , m_brt(brt)
    , m_state(0)
    , m_next(0)
{
    // No other initialization required.
}

void LedActivity::update(satcat5::cfg::NetworkStats* stats)
{
    // Minimum activity-LED "blink" time (in 1/30th second increments)
    static const unsigned ACTIVITY_SUSTAIN = 3;

    // New activity since last update?
    const satcat5::cfg::TrafficStats port = stats->get_port(m_stats_idx);
    u32 active = port.rcvd_frames + port.sent_frames;

    // Update LED based on new and recent activity:
    if (m_state > ACTIVITY_SUSTAIN) {
        // Turn LED back on after "winking".
        m_state = ACTIVITY_SUSTAIN; *m_reg = m_brt;
    } else if (active && m_state > 0) {
        // New activity with LED on -> Wink off.
        m_state = ACTIVITY_SUSTAIN + 1; *m_reg = 0;
    } else if (active) {
        // New activity with LED off -> LED on.
        m_state = ACTIVITY_SUSTAIN; *m_reg = m_brt;
    } else if (m_state > 0) {
        // Hold LED on until countdown reaches zero.
        --m_state; *m_reg = m_brt;
    } else {
        // No recent activity.
        *m_reg = 0;
    }
}

LedActivityCtrl::LedActivityCtrl(
        satcat5::cfg::NetworkStats* stats,
        unsigned delay)
    : m_stats(stats)
{
    timer_every(33);    // Updates ~30 Hz
}

void LedActivityCtrl::timer_event()
{
    // Refresh the NetworkStats object.
    m_stats->refresh_now();

    // Ask each registered LED to update.
    LedActivity* item = m_list.head();
    while (item) {
        item->update(m_stats);
        item = m_list.next(item);
    }
}

LedWave::LedWave(satcat5::cfg::ConfigBus* cfg,
        unsigned devaddr, unsigned regaddr, u8 brt)
    : m_reg(cfg->get_register(devaddr, regaddr))
    , m_brt(brt)
    , m_phase(0)
    , m_next(0)
{
    // No other initialization required.
}

void LedWave::update(u32 incr)
{
    // Increment phase, then index into lookup table [0..31]
    m_phase += incr;
    u8 tbl = SINE_ARRAY[m_phase >> 27];
    // Scale based on user brightness parameter.
    *m_reg = (((u32)tbl * (u32)m_brt) >> 8);
}

LedWaveCtrl::LedWaveCtrl()
    : m_incr(0)
{
    // No other initialization required.
}

void LedWaveCtrl::start(unsigned delay)
{
    // Set initial phase for each LED so they are equally spaced.
    unsigned count = m_list.len();
    u32 phase = 0, delta = UINT32_MAX / count;

    LedWave* item = m_list.head();
    while (item) {
        item->update(phase);
        phase += delta;
        item = m_list.next(item);
    }

    // Timer parameters give a full cycle every 2.0 seconds.
    m_incr = UINT32_MAX / 100;      // Phase increment per update
    timer_every(delay);             // Updates at specified interval
}

void LedWaveCtrl::stop()
{
    timer_stop();
}

void LedWaveCtrl::timer_event()
{
    // Forward timer event to each LED.
    LedWave* item = m_list.head();
    while (item) {
        item->update(m_incr);
        item = m_list.next(item);
    }
}
