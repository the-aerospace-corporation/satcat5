//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

// SatCat
#include <satcat5/polling.h>

// SAMV71 Drivers
extern "C" {
    #include <samv71.h>
};

// SatCat HAL
#include <hal_samv71/systick_timer.h>

using satcat5::sam::SysTickTimer;

//////////////////////////////////////////////////////////////////////////
// Registers & Constants
//////////////////////////////////////////////////////////////////////////

// SysTick Register Map
static const unsigned REGADDR_CTRL          = 0;
static const unsigned REGADDR_LOAD          = 1;
static const unsigned REGADDR_CURRENT_VALUE = 2;

// Constants
static const unsigned SYSTICK_CLK_BIT       = (1UL << 2UL);
static const unsigned SYSTICK_INT_BIT       = (1UL << 1UL);
static const unsigned SYSTICK_ENABLE_BIT    = (1UL << 0UL);

//////////////////////////////////////////////////////////////////////////
// Class
//////////////////////////////////////////////////////////////////////////

SysTickTimer::SysTickTimer(
    const u32 cpu_freq_hz,
    const u32 tick_rate_hz)
    : TimeRef(tick_rate_hz)
    , HandlerSAMV71("SysTick IRQ", SysTick_IRQn)
    , m_ctrl((u32*)SysTick_BASE)
    , m_callback(0)
{
    // Stop & Clear SysTick
    m_ctrl[REGADDR_CTRL]            = 0;
    m_ctrl[REGADDR_CURRENT_VALUE]   = 0;

    // Configure & Enable SysTick
    m_ctrl[REGADDR_LOAD] = (cpu_freq_hz / tick_rate_hz) - 1;
    m_ctrl[REGADDR_CTRL] = SYSTICK_CLK_BIT | SYSTICK_INT_BIT | SYSTICK_ENABLE_BIT;
}

u32 SysTickTimer::raw()
{
    return m_tick_num;
}

void SysTickTimer::timer_callback(poll::OnDemand* callback)
{
    m_callback = callback;
}

void SysTickTimer::irq_event()
{
    m_tick_num++;
    if (m_callback) m_callback->request_poll();
}

//////////////////////////////////////////////////////////////////////////
