//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! TimeRef and TimeVal define the API for monotonic timers.
//!
//! \details
//! The TimeRef API (formerly GenericTimer) provides various methods for
//! measuring elapsed time with a tick-counting time reference.
//!
//! A SatCat5 design may have many TimeRef objects.  The global "timekeeper"
//! (see polling.h) selects one as the preferred general-purpose system
//! reference.  Access the system reference using the SATCAT5_CLOCK macro,
//! which returns a TimeRef pointer.
//!
//! Each TimeRef may be backed by a hardware counter, a timer interrupt,
//! or software.  User-defined implementations must meet the following:
//!  * Override the "raw()" method to return the current tick count.
//!  * The counter must tick upwards monotonically at a fixed rate.
//!      * Supported tick rate of 1 kHz to 1 GHz.
//!      * Preferred tick rate of 1-100 MHz.
//!  * The counter must rollover from UINT32_MAX back to zero.
//!
//! SatCat5 provides several reference implementations:
//!  * cfg::Timer (satcat5/cfgbus_timer.h)
//!    Backing reference is a ConfigBus hardware timer (cfgbus_timer.vhd).
//!  * freertos::TickTimer (hal_freertos/tick_timer.h)
//!    Backing reference is the FreeRTOS system tick (xTaskGetTickCount).
//!  * util::PosixTimer (hal_posix/posix_utils.h)
//!    Backing reference is a POSIX monotonic clock (clock_gettime).
//!  * util::TimeRegister (this file)
//!    Backing reference is a memory-mapped address.

#pragma once

#include <satcat5/types.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace util {
        //! Timestamp for measuring elapsed time
        //!
        //! \link timeref.h SatCat5 system timer concepts. \endlink
        //!
        //! Timestamp value returned by TimeRef::now() and other methods.
        //! Represents a moment in time, either now or in the near future.
        struct TimeVal {
            TimeRef* clk;   //!< Pointer to the parent time reference.
            u32 tval;       //!< The value of this timestamp, measured in ticks.

            //! Measure elapsed time in ticks
            //!
            //! This example measures time spent in the "do_thing()" function:
            //! \code
            //!     TimeVal ref = SATCAT5_CLOCK->now();     // Create timestamp
            //!     do_thing();                             // Delay 42.7 usec
            //!     unsigned elapsed = ref.elapsed_usec();  // Returns 42
            //! \endcode
            unsigned elapsed_tick() const;
            //! Elapsed time in microseconds \see elapsed_tick
            unsigned elapsed_usec() const;
            //! Elapsed time in milliseconds \see elapsed_tick
            unsigned elapsed_msec() const;

            //! Measure elapsed time in microseconds, then increment.
            //!
            //! Measure elapsed time since the timestamp, then increment
            //! the timestamp by that integer quantity.  This is typically
            //! used to avoid cumulative rounding error for recurring events.
            //!
            //! This example measures time spent in the "do_thing()" function:
            //! \code
            //!     TimeVal ref = SATCAT5_CLOCK->now(); // Create timestamp
            //!     do_thing();                         // Delay 3.7 msec
            //!     unsigned t1 = ref.elapsed_msec();   // Returns 3
            //!     do_thing();                         // Delay 3.7 msec
            //!     unsigned t2 = ref.elapsed_msec();   // Returns 4
            //! \endcode
            unsigned increment_usec();
            //! Measure elapsed time in milliseconds, then increment.
            //! \copydetails increment_usec
            unsigned increment_msec();

            //! Test an interval measured in ticks.
            //!
            //! Measure elapsed time since the timestamp. If that exceeds
            //! the designated interval, then return true and increment
            //! the timestamp by the designated amount.  Otherwise, return
            //! false.  This is typically used to measure repeating events.
            //!
            //! This example prints a message once every second:
            //! \code
            //!     TimeVal ref = SATCAT5_CLOCK->now(); // Create timestamp
            //!     while (1) {                         // Poll forever...
            //!         if (ref.interval_msec(1000)) printf("Tock\n");
            //!     }
            //! \endcode
            bool interval_tick(u32 ticks);
            //! Test an interval measured in microseconds.
            //! \copydetails interval_tick
            bool interval_usec(unsigned usec);
            //! Test an interval measured in milliseconds.
            //! \copydetails interval_tick
            bool interval_msec(unsigned msec);

            //! Test if an oven-timer checkpoint has elapsed.
            //!
            //! If so, disable it (set to zero) and return true.
            //!
            //! To create a checkpoint, use methods TimeRef::checkpoint_usec()
            //! or TimeRef::checkpoint_msec().
            //!
            //! This example polls an object until a timeout has elapsed:
            //! \code
            //!     TimeVal timeout = SATCAT5_CLOCK->checkpoint_msec(100);
            //!     while (!timeout.checkpoint_elapsed()) {
            //!         do_thing();
            //!     }
            //! \endcode
            bool checkpoint_elapsed();
        };

        //! The TimeRef API provides access to a monotonic time-counter.
        //!
        //! \link timeref.h SatCat5 system timer concepts. \endlink
        //!
        //! If your project uses a custom time reference, make a custom class
        //! derived from the TimeRef base-class, and override the raw() method.
        //! To set that clock as the primary reference, call the timekeeper
        //! set_clock(...) or suggest_clock(...) methods. (See polling.h)
        class TimeRef {
        protected:
            //! Constructor accepts a scale-factor for conversion to real-time.
            //! (Only children should create or destroy the base class.)
            explicit constexpr TimeRef(u64 ticks_per_sec)
                : m_msec_per_tick(div_ceil<u64>(   1000ull << 32, ticks_per_sec))
                , m_usec_per_tick(div_ceil<u64>(1000000ull << 32, ticks_per_sec))
                , m_tick_per_msec(div_round<u64>(ticks_per_sec << 32,    1000ull))
                , m_tick_per_usec(div_round<u64>(ticks_per_sec << 32, 1000000ull))
                {}  // No other initialization required.
            ~TimeRef() {}

        private:
            friend satcat5::util::TimeVal;

            // Fixed-point scaling for conversion to/from engineering units.
            // (Internal use only, format is subject to change at any time.)
            u64 const m_msec_per_tick;   // 2^32 * 1K / FT
            u64 const m_usec_per_tick;   // 2^32 * 1M / FT
            u64 const m_tick_per_msec;   // 2^32 * FT / 1K
            u64 const m_tick_per_usec;   // 2^32 * FT / 1M

        public:
            //! Read current time in arbitrary "ticks".
            //! Tick-count MUST roll-over from UINT32_MAX to zero.
            //! Roll-over MUST NOT occur more than once per second.
            //! (Child class MUST define this method.)
            virtual u32 raw() = 0;

            //! Create a TimeVal object using the tick-count from raw().
            TimeVal now();

            //! Stable accessors for unit conversion.
            //! If the tick rate is low, these may return zero.
            //!@{
            inline u32 ticks_per_sec() const
                { return u32((1000 * m_tick_per_msec) >> 32); }
            inline u32 ticks_per_msec() const
                { return u32(m_tick_per_msec >> 32); }
            inline u32 ticks_per_usec() const
                { return u32(m_tick_per_usec >> 32); }
            //!@}

            //! Create an oven-timer, set N microseconds from now.
            //! An over-timer TimeVal is a timestamp a short time in the future.
            //! To use it, create the TimeVal and then poll checkpoint_elapsed().
            //! (The returned TimeVal is intended to be used exactly once.)
            TimeVal checkpoint_usec(unsigned usec);
            //! Create an oven-timer, set N milliseconds from now.
            //! \copydetails checkpoint_usec
            TimeVal checkpoint_msec(unsigned msec);

            //! If timer resolution allows, busywait for X microseconds.
            //! (May return immediately if backing reference is too coarse.)
            void busywait_usec(unsigned usec);
        };

        //! Placeholder used if no timer is available.
        class NullTimer : public satcat5::util::TimeRef {
        public:
            NullTimer() : TimeRef(1) {}
            u32 raw() override {return 0;}
        };

        //! Implement TimeRef API using a memory-mapped performance counter.
        //! (i.e., A read-only register that reports elapsed clock cycles.)
        //! Note: The register MUST roll-over from UINT32_MAX to zero.
        class TimeRegister final : public satcat5::util::TimeRef
        {
        public:
            constexpr TimeRegister(volatile u32* reg, u32 clkref_hz)
                : TimeRef(clkref_hz), m_reg(reg) {}
            ~TimeRegister() {}

            u32 raw() override;     // Return counter register value

        private:
            volatile u32* m_reg;    // Pointer to the counter register
        };
    }
}
