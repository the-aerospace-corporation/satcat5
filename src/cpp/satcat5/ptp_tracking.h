//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Closed-loop time-tracking clocks and tracking control
//!
//!\details
//! This file defines several classes:
//!  * ptp::TrackingClock is a generic interface for an adjustable
//!      clock reference, allowing stepwise changes and rate changes.
//!  * ptp::TrackingController accepts a series of timestamped error
//!      measurements (e.g., from an NTP or PTP client) and commands
//!      a TrackingClock to precisely match the correct time. The control
//!      logic is configurable using daisy-chained ptp::Filter objects.
//!  * ptp::TrackingSimple is a wrapper for TrackingController that
//!      integrates a typical filter chain; it yields good performance
//!      in many scenarios, so it can be used as-is or as an example.
//!  * ptp::TrackingCoarse is an alternative to TrackingController that
//!      does not attempt fine tracking or guarantee monotonicity.  For
//!      simplicity, it only makes stepwise adjustments to the clock.

#pragma once

#include <satcat5/list.h>
#include <satcat5/polling.h>
#include <satcat5/ptp_filters.h>
#include <satcat5/ptp_measurement.h>
#include <satcat5/ptp_source.h>
#include <satcat5/ptp_time.h>
#include <satcat5/timeref.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace ptp {
        //! Define rate offsets for the TrackingClock::clock_rate() method.
        //! Units are normalized, 2^16 LSB = 1 PPB = 1 nanosecond per second.
        //! Zero indicates the clock's free-wheeling rate.
        //!@{
        constexpr s64 RATE_ONE_PPB  = satcat5::ptp::SUBNS_PER_NSEC;
        constexpr s64 RATE_ONE_PPM  = 1000 * satcat5::ptp::RATE_ONE_PPB;
        constexpr s64 RATE_ONE_PPK  = 1000 * satcat5::ptp::RATE_ONE_PPM;
        //!@}

        //! Generic interface to a numerically-controlled reference clock.
        //! * Clock implementations MUST override each of the methods below.
        //! * The "clock_rate" implementation MUST store the input to m_offset.
        //! * Implementations SHOULD provide a constant or constexpr function
        //!   to calculate "ref_scale" for loop filters (see "ptp_filters.h").
        //! \see ptp_tracking.h
        class TrackingClock {
        public:
            //! Return the current time if available, TIME_ZERO otherwise.
            virtual satcat5::ptp::Time clock_now() = 0;

            //! Make a one-time adjustment of the specified magnitude.
            //! Positive quantities indicate the clock should move forward.
            //! Return value is the estimated remainder or residual error.
            virtual satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) = 0;

            //! Adjust rate by a normalized frequency offset.
            //! Positive offsets command the clock to run faster.
            //! (See discussion above, near definition of RATE_ONE_PPB.)
            virtual void clock_rate(s64 offset) = 0;

            //! Read the current clock-tuning parameter.
            //! \returns The most recent value passed to "clock_rate", above.
            s64 get_rate() const {return m_offset;}

        protected:
            //! Protected constructor should only be called by the child.
            constexpr TrackingClock() : m_offset(0), m_next(0) {}
            s64 m_offset;

        private:
            // Pointer to the next element in a linked list.
            friend satcat5::util::ListCore;
            satcat5::ptp::TrackingClock* m_next;
        };

        //! Clock controller handling coarse and fine discipline.
        //! High-level control for initial acquisition and tracking, applying
        //! a chain of ptp::Filter objects to derive the final control signal
        //! from a raw series of measurements.  See also: "ptp_filters.h".
        //! The output is passed to a TrackingClock object.
        //! \see ptp_tracking.h
        class TrackingController : public satcat5::ptp::Callback {
        public:
            //! Constructor links to a specific TrackingClock target.
            //! Note: It is safe to provide a null TrackingClock pointer.
            TrackingController(
                satcat5::ptp::TrackingClock* clk,
                satcat5::ptp::Source* source = 0);

            //! Event handler for ptp::Callback.
            //! This calculates offsetFromMaster and calls "update".
            void ptp_ready(const satcat5::ptp::Measurement& data) override;

            //! Add to the list of attached clocks.
            //! All will receive the same frequency adjustments and
            //! will be frequency-locked, but only the primary clock
            //! (constructor or first add_clock) will be phase-locked.
            inline void add_clock(satcat5::ptp::TrackingClock* clock)
                { m_clocks.push_front(clock); }
            //! Remove an item from the list of attached clocks.
            inline void remove_clock(satcat5::ptp::TrackingClock* clock)
                { m_clocks.remove(clock); }

            //! Add to the chain of processing filters. \see ptp_filters.h
            //! A chain of filters condition raw measurements at the input,
            //! deriving the final control signal for the TrackingClock.
            //! Filters are added and applied in the same sequence, with each
            //! new filter added to the end of the pre-existing chain.
            inline void add_filter(satcat5::ptp::Filter* filter)
                { m_filters.push_back(filter); }

            //! Remove a filter from the chain, leaving others as-is.
            //! e.g., Starting from A->B->C, removing B results in A->C.
            inline void remove_filter(satcat5::ptp::Filter* filter)
                { m_filters.remove(filter); }

            //! Reset tracking filter(s) and begin free-wheeling.
            //! \param linear Disables nonlinear coarse acquisition.
            void reset(bool linear=false);

            //! Update filter state with a new measurement from the PTP client.
            //! Specify the measured clock offset (delta = remote - local).
            //! (Call this directly or use the ptp::Callback event handler.)
            void update(const satcat5::ptp::Time& delta);

        protected:
            // Coarse acquisition and lock/unlock state.
            s64 coarse(const satcat5::ptp::Time& delta);

            // Run each filter one timestep.
            void filter(u32 elapsed_usec, s64 delta_subns);

            // Notify each registered clock object.
            // The primary clock (first added) sets the return value.
            satcat5::ptp::Time clock_adjust(const satcat5::ptp::Time& amount);
            void clock_rate(s64 offset);

            // Internal state for fast-acquisition mode.
            enum class LockState {RESET, ACQUIRE, TRACK, LINEAR};

            // Internal state.
            satcat5::util::List<satcat5::ptp::TrackingClock> m_clocks;
            satcat5::util::List<satcat5::ptp::Filter> m_filters;
            satcat5::util::TimeVal m_tref;
            s64 m_freq_accum;
            u32 m_lock_alarm;
            u32 m_lock_usec;
            satcat5::ptp::TrackingController::LockState m_lock_state;
        };

        //! Simple all-in-one implementation of TrackingController.
        //! Streamlined variant of ptp::TrackingController, with a built-in
        //! filter chain that is adequate for most PTP applications.
        //! \see ptp_tracking.h TrackingController
        class TrackingSimple : public satcat5::ptp::TrackingController {
        public:
            //! Constructor links to a specific TrackingClock target.
            TrackingSimple(
                satcat5::ptp::TrackingClock* clk,
                satcat5::ptp::Source* source);

        protected:
            satcat5::ptp::AmplitudeReject m_ampl;
            satcat5::ptp::ControllerPII m_ctrl;
        };

        //! Bang-bang alternative to TrackingController.
        //! Crude controller for coarse time adjustments, making no attempt at
        //! fine-tuned rate adjustment. This block is not suitable for precise
        //! timing, but it is substantially simpler than other alternatives.
        //! \see ptp_tracking.h TrackingController
        class TrackingCoarse : public satcat5::ptp::Callback {
        public:
            //! Constructor links to a specific TrackingClock target.
            TrackingCoarse(
                satcat5::ptp::TrackingClock* clk,
                satcat5::ptp::Source* source);

            //! Event handler for ptp::Callback.
            void ptp_ready(const satcat5::ptp::Measurement& data) override;

        protected:
            // Internal state.
            satcat5::ptp::TrackingClock* m_clock;
        };
    }
}
