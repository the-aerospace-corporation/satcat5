//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// GenericTimer interface
//
// Define the GenericTimer interface, which provides various methods for
// interacting with a cycle-counting timer.
//
// The GenericTimer interface is designed to be readily adaptable to various
// user-defined timers.  Refer to "satcat5/cfgbus_timer.h" (cfg::Timer) or
// "hal_test/sim_utils.h" (PosixTimer) for example implementations.
//

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace util {
        // Extremely basic interface for a generic time-counter.
        // (If your project uses a custom time reference, make a custom wrapper
        //  that derives from this interface definition.)
        class GenericTimer
        {
        protected:
            // Constructor accepts a scale-factor for conversion to real-time.
            // (Only children should create or destroy the base class.)
            explicit constexpr GenericTimer(u32 ticks_per_usec)
                : m_ticks_per_usec(ticks_per_usec)
                , m_ticks_per_msec(1000*ticks_per_usec)
                {}  // No other initialization required.
            ~GenericTimer() {}

        public:
            // Read current time in arbitrary "ticks".
            // Tick-count MUST roll-over from UINT32_MAX to zero.
            // Roll-over MUST NOT occur more than once per second.
            // (Child class MUST define this method.)
            virtual u32 now() = 0;

            // Measure elapsed time since TREF, in ticks.
            u32 elapsed_ticks(u32 tref);

            // Measure elapsed time since TREF, in microseconds.
            unsigned elapsed_usec(u32 tref);

            // As elapsed_usec, but also increment TREF.
            unsigned elapsed_incr(u32& tref);

            // As elapsed_incr, but units in milliseconds.
            unsigned elapsed_msec(u32& tref);

            // Test if a given interval has elapsed since TREF.
            // If so, increment TREF for the next interval.
            bool elapsed_test(u32& tref, unsigned usec);

            // Set an oven-timer checkpoint N microseconds in the future.
            u32 get_checkpoint(unsigned usec);

            // Test if a timer checkpoint TREF has elapsed.
            // If so, disable it and return true.
            bool checkpoint_elapsed(u32& tref);

            // Busywait for X microseconds.
            void busywait_usec(unsigned usec);

            // Time conversion factor
            u32 const m_ticks_per_usec;
            u32 const m_ticks_per_msec;
        };

        // Implement GenericTimer using a memory-mapped performance counter.
        // (i.e., A read-only register that reports elapsed clock cycles.)
        // Note: The register MUST roll-over from UINT32_MAX to zero.
        class TimerRegister final : public satcat5::util::GenericTimer
        {
        public:
            TimerRegister(volatile u32* reg, u32 clkref_hz);
            ~TimerRegister() {}

            u32 now() override;

        private:
            volatile u32* m_reg;    // Pointer to the counter register
        };
    }
}
