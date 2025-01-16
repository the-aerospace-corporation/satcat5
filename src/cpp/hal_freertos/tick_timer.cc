//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

// FreeRTOS includes
extern "C"{
    #include <FreeRTOS.h>
    #include <FreeRTOSConfig.h>
    #include <task.h>
};

#include <hal_freertos/tick_timer.h>

using satcat5::freertos::TickTimer;

TickTimer::TickTimer()
    : TimeRef(configTICK_RATE_HZ)
{
    satcat5::poll::timekeeper.suggest_clock(this);
}

u32 TickTimer::raw()
{
    return (u32) xTaskGetTickCount();
}

//////////////////////////////////////////////////////////////////////////
