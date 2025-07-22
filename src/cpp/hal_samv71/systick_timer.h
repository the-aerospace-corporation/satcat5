//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Microchip SAM V71 implementation of the "TimeRef" API.

#pragma once

#include <satcat5/timeref.h>
#include <satcat5/cfgbus_core.h>
#include <hal_samv71/interrupt_handler.h>

namespace satcat5 {
    namespace sam {
        //! Microchip SAM V71 implementation of the "TimeRef" API.
        //! This class uses configures and uses the SysTick Timer on the SAMV71 to
        //! track elapsed time for SatCat. At instantiation, it uses the CPU
        //! frequency and desired tick rate to configure the interrupt. It will
        //! will increment member when the interrupt is triggered, and SatCat
        //! can poll this value to find elapsed time.
        class SysTickTimer
            : public satcat5::util::TimeRef
            , public satcat5::sam::HandlerSAMV71 {
        public:
            //! Constructor requires the CPU frequency and timer tick-rate.
            SysTickTimer(
                const u32 cpu_freq_hz,
                const u32 tick_rate_hz);

            //! Get raw tick-count, \see TimeRef.
            u32 raw() override;

            //! Set callback for timer events.
            //! (This is usually poll::timekeeper.)
            void timer_callback(satcat5::poll::OnDemand* callback);

        protected:
            // SysTick ISR
            void irq_event() override;

            // SysTick Registers
            u32* m_ctrl;

            // Tick Count
            unsigned int m_tick_num = 0;

            // Callback Function
            satcat5::poll::OnDemand* m_callback;
        };
    }  // namespace sam
}  // namespace satcat5
