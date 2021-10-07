//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_timer.h>
#include <satcat5/polling.h>

namespace cfg = satcat5::cfg;

// ConfigBus watchdog starts in the paused state.
//  * Writing the special PAUSE value stops the watchdog.
//  * Writing any other value resets the countdown to that value.
//    Without intervention, the watchdog will trigger after N ticks.
static const u32 WDOG_PAUSE = (u32)(-1);

// Define the hardware register map:
static const unsigned REGADDR_WDOG       = 0;
static const unsigned REGADDR_CPU_HZ     = 1;
static const unsigned REGADDR_PERF_CTR   = 2;
static const unsigned REGADDR_LAST_EVT   = 3;
static const unsigned REGADDR_TIMER_LEN  = 4;
static const unsigned REGADDR_TIMER_IRQ  = 5;

inline u32 ticks_per_usec(cfg::ConfigBus* cfg, unsigned devaddr)
{
    cfg::Register reg = cfg->get_register(devaddr);
    u32 cpu_hz = reg[REGADDR_CPU_HZ];
    return cpu_hz / 1000000;
}

cfg::Timer::Timer(cfg::ConfigBus* cfg, unsigned devaddr)
    : satcat5::util::GenericTimer(ticks_per_usec(cfg, devaddr))
    , cfg::Interrupt(cfg, devaddr, REGADDR_TIMER_IRQ)
    , m_ctrl(cfg->get_register(devaddr))
    , m_callback(0)
{
    m_ctrl[REGADDR_WDOG] = WDOG_PAUSE;
}

u32 cfg::Timer::now()
{
    return m_ctrl[REGADDR_PERF_CTR];
}

u32 cfg::Timer::last_event()
{
    return m_ctrl[REGADDR_LAST_EVT];
}

void cfg::Timer::timer_interval(unsigned usec)
{
    m_ctrl[REGADDR_TIMER_LEN] = usec * m_ticks_per_usec - 1;
}

void cfg::Timer::timer_callback(poll::OnDemand* callback)
{
    m_callback = callback;
}

void cfg::Timer::wdog_disable()
{
    m_ctrl[REGADDR_WDOG] = WDOG_PAUSE;
}

void cfg::Timer::wdog_update(u32 usec)
{
    m_ctrl[REGADDR_WDOG] = usec * m_ticks_per_usec;
}

void cfg::Timer::irq_event()
{
    if (m_callback) m_callback->request_poll();
}
