//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Tools for simulation and unit testing of PTP clocks

#pragma once

#include <hal_test/sim_utils.h>
#include <satcat5/ptp_filters.h>
#include <satcat5/ptp_measurement.h>
#include <satcat5/ptp_time.h>
#include <satcat5/ptp_tracking.h>

namespace satcat5 {
    namespace ptp {
        // Simulated clock mimics operation of "ptp_realtime.vhd"
        class SimulatedClock : public satcat5::ptp::TrackingClock {
        public:
            // 1 LSB = 2^-40 nanoseconds = 2^-24 subns
            // (This matches the default for ptp_counter_gen and ptp_realtime.)
            static constexpr unsigned TICK_SCALE_NSEC = 40;
            static constexpr u64 TICKS_PER_SUBNS =
                (1ull << TICK_SCALE_NSEC) / u64(satcat5::ptp::SUBNS_PER_NSEC);
            static constexpr double TICKS_PER_SEC =
                double(TICKS_PER_SUBNS) * double(satcat5::ptp::SUBNS_PER_SEC);

            // Constructor allows user to set desired accuracy.
            SimulatedClock(double nominal_hz, double actual_hz);

            // Confirm initial configuration is valid.
            inline bool ok() const
                { return m_scale_nominal.ok(); }

            // Report the number of coarse and fine adjustments.
            inline unsigned num_coarse() const
                { return m_count_coarse; }
            inline unsigned num_fine() const
                { return m_count_fine; }

            // Mean of all inputs to clock_rate(...)
            inline double mean() const
                { return m_stats.mean(); }

            // Implement the required TrackingClock API.
            satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) override;
            satcat5::ptp::Time clock_now() override;
            void clock_rate(s64 offset) override;
            double clock_offset_ppm() const;
            void clock_set(const satcat5::ptp::Time& t);

            // Advance simulation by X seconds.
            void run(const satcat5::ptp::Time& dt);

        private:
            const satcat5::ptp::RateConversion m_scale_nominal;
            const double m_rate_actual;
            const s64 m_nco_rate;
            satcat5::util::uint128_t m_nco_accum;
            unsigned m_count_coarse;
            unsigned m_count_fine;
            satcat5::ptp::Time m_rtc;
            satcat5::test::Statistics m_stats;
        };

        // Helper object for tracking simulation time.
        class SimulatedTimer : public satcat5::ptp::Source {
        public:
            SimulatedTimer();
            inline satcat5::util::TimeRef* get_timer()
                {return &m_timer;}

            // Advance simulation by X seconds.
            void run(const satcat5::ptp::Time& dt);

        protected:
            u32 m_treg;
            satcat5::util::TimeRegister m_timer;
        };
    }
}
