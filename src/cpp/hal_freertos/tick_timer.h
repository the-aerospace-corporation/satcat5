//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
// This class uses the FreeRTOS API to track elapsed time for SatCat. It
// leverages the FreeRTOS API and configured tick rate of FreeRTOS.

#pragma once

#include <satcat5/timeref.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace freertos {
        class TickTimer : public satcat5::util::TimeRef {
        public:
            // Constructor.
            TickTimer();

            // Get Tick Count
            u32 raw() override;
        };
    }  // namespace freertos
}  // namespace satcat5

//////////////////////////////////////////////////////////////////////////

