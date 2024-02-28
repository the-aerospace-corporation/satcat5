//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Closed-loop time-tracking filter for high-precision NCOs.
//
// This file defines a "ptp::TrackingController" object that accepts a series
// of timestamped error measurements, applies a control filter to achieve
// the specified settling time, and uses that output to precisely adjust
// a numerically-controlled oscillator (NCO) to track another time reference.
// The NCO must implement the provided "ptp::TrackingClock" interface to
// provide a consistent API for coarse and fine adjustements.
//

#pragma once

#include <satcat5/datetime.h>
#include <satcat5/polling.h>
#include <satcat5/ptp_filters.h>
#include <satcat5/ptp_measurement.h>
#include <satcat5/ptp_time.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace ptp {
        // Generic interface to a numerically-controlled reference clock.
        // * Clock implementations MUST override each of the methods below.
        // * The "clock_rate" implementation MUST store the input to m_offset.
        // * Implementations SHOULD provide a constant or constexpr function
        //   to calculate "ref_scale" for loop filters (see "ptp_filters.h").
        class TrackingClock {
        public:
            // Make a one-time adjustment of the specified magnitude.
            // Positive quantities indicate the clock should move forward.
            // Return value is the estimated remainder or residual error.
            virtual satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) = 0;

            // Adjust rate by the specified frequency offset.
            // Units are arbitrary (i.e., ticks per unit time) with zero
            // indicating the clock's free-wheeling rate, and positive
            // values indicating that the clock should run faster.
            virtual void clock_rate(s64 offset) = 0;

            // Returns the most recent value passed to "clock_rate", above.
            s64 get_rate() const {return m_offset;}

        protected:
            // Protected constructor.
            TrackingClock() : m_offset(0) {}
            s64 m_offset;
        };

        // The TrackingDither adapter adds delta-sigma dither for enhanced
        // resolution, to mitigate quantization limits in the TrackingClock.
        // By rapidly updating the rate and systematically opting to round
        // up or down on each iteration, it can provide sub-LSB resolution.
        class TrackingDither
            : public satcat5::poll::Timer
            , public satcat5::ptp::TrackingClock
        {
        public:
            // Constructor takes a pointer to the underlying clock object.
            explicit TrackingDither(satcat5::ptp::TrackingClock* clk);

            // Override all required methods.
            satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) override;
            void clock_rate(s64 offset);

            // This adapter decreases effective "ref_scale" by a fixed factor.
            static constexpr double ref_scale(double inner_scale)
                { return inner_scale / 65536.0; }

        protected:
            // Apply new dither on each Timer event.
            void timer_event() override;

            satcat5::ptp::TrackingClock* const m_clk;
            u16 m_disparity;
        };

        // High-level control for initial acquisition and tracking, applying
        // a chain of ptp::Filter objects to derive the final control signal
        // from a raw series of measurements.  See also: "ptp_filters.h".
        // The output is passed to a TrackingClock object.
        class TrackingController : public satcat5::ptp::Callback {
        public:
            // Constructor links to a specific TrackingClock target
            // and sets loop bandwidth, which can be changed later.
            TrackingController(
                satcat5::util::GenericTimer* timer,
                satcat5::ptp::TrackingClock* clk,
                satcat5::ptp::Client* client);

            // Event handler for ptp::Callback.
            // This calculates offsetFromMaster and calls "update".
            void ptp_ready(const satcat5::ptp::Measurement& data) override;

            // Add to the chain of processing filters. (See "ptp_filters.h").
            // A chain of filters condition raw measurements at the input,
            // deriving the final control signal for the TrackingClock.
            // Filters are added and applied in the same sequence, with each
            // new filter added to the end of the pre-existing chain.
            inline void add_filter(satcat5::ptp::Filter* filter)
                { m_filters.push_back(filter); }

            // Remove a filter from the chain, leaving others as-is.
            // e.g., Starting from A->B->C, removing B results in A->C.
            inline void remove_filter(satcat5::ptp::Filter* filter)
                { m_filters.remove(filter); }

            // Reset tracking filter(s) and begin free-wheeling.
            void reset();

            // Update filter state with a new measurement from the PTP client.
            // Specify the measured clock offset (delta = remote - local).
            // (Call this directly or use the ptp::Callback event handler.)
            void update(const satcat5::ptp::Time& delta);

        protected:
            // Coarse acquisition and lock/unlock state.
            s64 coarse(const satcat5::ptp::Time& delta);

            // Run each filter one timestep.
            void filter(u32 elapsed_usec, s64 delta_subns);

            enum class LockState {RESET, ACQUIRE, TRACK};

            // Internal state.
            satcat5::util::GenericTimer* const m_timer;
            satcat5::ptp::TrackingClock* const m_clk;
            satcat5::util::List<satcat5::ptp::Filter> m_filters;
            u32 m_tref;
            s64 m_freq_accum;
            u32 m_lock_alarm;
            u32 m_lock_usec;
            satcat5::ptp::TrackingController::LockState m_lock_state;
        };
    }
}
