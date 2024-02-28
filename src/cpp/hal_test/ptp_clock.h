//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Tools for simulation and unit testing of PTP clocks

#pragma once

#include <hal_test/sim_utils.h>
#include <satcat5/ptp_time.h>
#include <satcat5/ptp_tracking.h>

namespace satcat5 {
    namespace ptp {
        // Simulated clock mimics operation of "ptp_realtime.vhd"
        class SimulatedClock : public satcat5::ptp::TrackingClock {
        public:
            // 1 LSB = 2^-40 nanoseconds = 2^-24 subns
            // (This matches the default for ptp_counter_gen and ptp_realtime.)
            static constexpr u64 TICKS_PER_SUBNS = (1ull << 24);
            static constexpr double TICKS_PER_SEC =
                double(TICKS_PER_SUBNS) * double(satcat5::ptp::SUBNS_PER_SEC);

            // Constructor allows user to set desired accuracy.
            SimulatedClock(double nominal_hz, double actual_hz);

            // Report the number of coarse and fine adjustments.
            inline unsigned num_coarse() const
                { return m_count_coarse; }
            inline unsigned num_fine() const
                { return m_count_fine; }

            // Mean of all inputs to clock_rate(...)
            inline double mean() const
                { return m_stats.mean(); }

            // Accessor for the current real-time-clock (RTC) state.
            inline satcat5::ptp::Time now() const
                { return m_rtc; }

            // Implement the required TrackingClock API.
            satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) override;
            void clock_rate(s64 offset) override;
            double clock_offset_ppm() const;
            double ref_scale() const;

            // Advance simulation by X seconds.
            void run(const satcat5::ptp::Time& dt);

        private:
            const double m_scale_nominal;
            const double m_rate_actual;
            const s64 m_nco_rate;
            satcat5::util::uint128_t m_nco_accum;
            unsigned m_count_coarse;
            unsigned m_count_fine;
            satcat5::ptp::Time m_rtc;
            satcat5::test::Statistics m_stats;
        };
    }
}
