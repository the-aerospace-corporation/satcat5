//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Driver for the ConfigBus timer.

#pragma once

#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/timer.h>

namespace satcat5 {
    namespace cfg {
        // ConfigBus Timer driver (cfgbus_timer.vhd)
        class Timer
            : public satcat5::util::GenericTimer
            , protected satcat5::cfg::Interrupt
        {
        public:
            // Constructor.
            Timer(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            // Read current time.
            // Note: This is the only "required" timer function.
            //       Everything else is specific to the ConfigBus timer.
            u32 now() override;

            // Read time of the last external "event" trigger.
            u32 last_event();

            // Change the timer-interrupt interval (default = 1 msec).
            void timer_interval(unsigned usec);

            // Set the callback for timer-interrupt notifications.
            void timer_callback(satcat5::poll::OnDemand* callback);

            // Control the watchdog timer
            void wdog_disable();            // Disable watchdog timer
            void wdog_update(u32 usec);     // Resume/reset watchdog countdown

        protected:
            // Timer interrupt handler.
            void irq_event() override;

            // Link to the hardware register map.
            satcat5::cfg::Register m_ctrl;

            // Callback object is polled after each timer interrupt.
            satcat5::poll::OnDemand* m_callback;
        };
    }
}
