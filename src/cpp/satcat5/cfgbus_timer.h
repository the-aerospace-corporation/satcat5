//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Driver for the ConfigBus timer.

#pragma once

#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/timeref.h>

namespace satcat5 {
    namespace cfg {
        //! ConfigBus Timer driver.
        //! Device driver for the timer system defined in "cfgbus_timer.vhd".
        //! The primary purpose of this device is to act as a cycle-counting
        //! `TimeRef` (typically operating at 10 to 100 MHz), and an interrupt
        //! source at a programmable interval (typically at 1 kHz).  In some
        //! designs, it may also act as a watchdog timer that resets the system
        //! if it has not been updated after some interval.
        class Timer
            : public satcat5::util::TimeRef
            , protected satcat5::cfg::Interrupt
        {
        public:
            //! Auto-configuration constructor.
            //! This constructor reads frequency parameters at runtime.
            Timer(satcat5::cfg::ConfigBus* cfg, unsigned devaddr)
                : Timer(cfg, devaddr, hw_ticks_per_sec(cfg, devaddr)) {}

            //! Manual-configuration constructor.
            //! If the timer's clock frequency is known at build time, this
            //! alternate constructor can avoid runtime division calls.
            inline Timer(satcat5::cfg::ConfigBus* cfg, unsigned devaddr, u32 refclk_hz)
                : TimeRef(refclk_hz)
                , Interrupt(cfg, devaddr, REGADDR_TIMER_IRQ)
                , m_ctrl(cfg->get_register(devaddr))
                , m_callback(0)
            {
                m_ctrl[REGADDR_WDOG] = WDOG_PAUSE;
            }

            //! Read the current time.
            //! This method is required for the TimeRef API.
            //! \returns Clock-cycle counter, modulo 2^32.
            u32 raw() override;

            //! Read timestamp of the last external event signal.
            //! If enabled at build time, the Timer can note the timestamp of
            //! the most recent rising edge of a discrete "event" signal.
            //! For a more precise equivalent, see satcat5::ptp::PpsInput.
            satcat5::util::TimeVal last_event();

            //! Change the timer-interrupt interval.
            //! On startup/reset, the default interval is 1 millisecond.
            //! This method sets a new interval, measured in microseconds.
            void timer_interval(unsigned usec);

            //! Set the callback for timer-interrupt notifications.
            //! In most designs, this should be linked to satcat5::poll::timekeeper.
            void timer_callback(satcat5::poll::OnDemand* callback);

            //! Disable the hardware watchdog function.
            //! A disabled watchdog returns to its default idle state, which
            //! stops the countdown and never requests a hardware reset.
            //! To start or resume the countdown, call `wdog_update`.
            void wdog_disable();

            //! Resume or reset the watchdog countdown.
            //! Enables the watchdog function and set the countdown timer
            //! to the designated interval, in microseconds.  Within that
            //! interval, the user should call `wdog_update` again to prevent
            //! a reset request, or call `wdog_disable` to stop the countdown.
            void wdog_update(u32 usec);

        protected:
            // Writing the special PAUSE value stops the watchdog.
            static constexpr u32 WDOG_PAUSE = (u32)(-1);

            // Define the hardware register map:
            static constexpr unsigned REGADDR_WDOG       = 0;
            static constexpr unsigned REGADDR_CPU_HZ     = 1;
            static constexpr unsigned REGADDR_PERF_CTR   = 2;
            static constexpr unsigned REGADDR_LAST_EVT   = 3;
            static constexpr unsigned REGADDR_TIMER_LEN  = 4;
            static constexpr unsigned REGADDR_TIMER_IRQ  = 5;

            // Access REGADDR_CPU_HZ before m_ctrl is initialized.
            static inline u32 hw_ticks_per_sec(satcat5::cfg::ConfigBus* cfg, unsigned devaddr) {
                satcat5::cfg::Register reg = cfg->get_register(devaddr);
                return reg[REGADDR_CPU_HZ];
            }

            // Timer interrupt handler.
            void irq_event() override;

            // Link to the hardware register map.
            satcat5::cfg::Register m_ctrl;

            // Callback object is polled after each timer interrupt.
            satcat5::poll::OnDemand* m_callback;
        };
    }
}
