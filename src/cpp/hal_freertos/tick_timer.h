//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// SatCat5 time reference using the FreeRTOS tick counter.

#pragma once

#include <satcat5/timeref.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace freertos {
        //! SatCat5 time reference using the FreeRTOS tick counter.
        //! This class implements the `TimeRef` API, measuring elapsed
        //! time using the tick counter, i.e., "xTaskGetTickCount" and
        //! "configTICK_RATE_HZ".  Time resolution is relatively coarse,
        //! but this API is available on any FreeRTOS platform.
        class TickTimer : public satcat5::util::TimeRef {
        public:
            //! Construct the TickTimer object.
            //! Automatically calls `Timekeeper::suggest_clock`.
            TickTimer();

            //! Get FreeRTOS Tick Count.
            u32 raw() override;
        };
    }  // namespace freertos
}  // namespace satcat5
