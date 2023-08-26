//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// Closed-loop time-tracking filter for high-precision NCOs.
//
// This file defines a "ptp::TrackingFilter" object that accepts a series
// of timestamped error measurements, applies a control filter to achieve
// the specified settling time, and uses that output to precisely adjust
// a numerically-controlled oscillator (NCO) to track another time reference.
// The NCO must implement the provided "ptp::TrackingClock" interface to
// provide a consistent API for coarse and fine adjustements.
//
// Internally, the loop-filter uses a proportional-integral (PI) algorithm.
// The loop filter runtime is implemented using fixed-point arithmetic.
// However, certain build-time calculations use floating-point, including
// the initial calculation of filter coefficients.

#pragma once

#include <satcat5/polling.h>
#include <satcat5/ptp_time.h>
#include <satcat5/uint_wide.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace ptp {
        // Generic interface to a numerically-controlled reference clock.
        // * Clock implementations MUST override each of the methods below.
        // * Implementations SHOULD provide a constant or constexpr function
        //   to calculate "ref_scale" for TrackingCoeff (see below).
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
        };

        // Passthrough implementation of TrackingClock that remembers the
        // last rate setting. Useful for debugging and diagnostics.
        class TrackingClockDebug : public satcat5::ptp::TrackingClock {
        public:
            explicit constexpr TrackingClockDebug(
                satcat5::ptp::TrackingClock* target)
                : m_target(target), m_rate(0) {}
            satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) override;
            void clock_rate(s64 offset) override;
            s64 clock_rate() const {return m_rate;}

        protected:
            satcat5::ptp::TrackingClock* const m_target;
            s64 m_rate;
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
            s64 m_offset;
        };

        // Calculate loop-filter coefficients to achieve a given step response.
        // All floating-point calculations can be run at build-time.
        //
        // The process requires three arguments:
        // * "ref_scale" is a unitless quantity that indicates the scaling
        //   factor for calls to "clock_rate()" (see above).  It is measured
        //   in seconds-per-second per LSB, i.e., a value of X indicates that
        //   an offset of one LSB, sustained for one second, shifts RefClock
        //   by a total of X seconds.  For best results, this quantity should
        //   be less than 10^-10.  For less precise clocks, use RefDither.
        // * "tau_secs" is the desired filter time constant in seconds.
        //   A time constant of about 5.0 seconds is typical.
        // * "damping" is the unitless damping ratio, zeta.
        //   Default 0.707 is slightly underdamped for reduced settling time.
        //
        // See also: Stephens & Thomas, "Controlled-root formulation for
        //  digital phase-locked loops", IEEE Transactions on Aerospace and
        //  Electronic Systems 1995, doi: 10.1109/7.366295.
        // https://ieeexplore.ieee.org/abstract/document/366295
        struct TrackingCoeff {
        public:
            // Calculate tracking-loop coefficients.
            constexpr TrackingCoeff(
                double ref_scale, double tau_secs, double damping = 0.707)
                : kp(safe_round(k1(tau_secs, damping) / fw_gain(ref_scale)))
                , ki(safe_round(k2(tau_secs, damping) / fw_gain(ref_scale)))
                , ymax(safe_round(slew_limit(ref_scale)))
                {} // No other initialization required.

            // Are both coefficients large enough to mitigate rounding error?
            bool ok() const {return (kp > 7) && (ki > 7);}

            // Fixed-point scaling of each coefficient by 2^-N.
            // Optimized for time constants circa 5-3600 seconds.
            static constexpr unsigned SCALE = 60;

        protected:
            // Fail loudly on integer overflow.
            static constexpr u64 safe_round(double x)
                { return (x < UINT64_MAX) ? satcat5::util::round_u64(x) : 0; }
            // Calculate alpha2, K1, and K2 from Stephens & Thomas Table II.
            // Note: Omit scaling by T0; compensate for this at runtime.
            static constexpr double alpha(double zeta)
                { return 0.25 / (zeta * zeta); }
            static constexpr double k1(double tau, double zeta)
                { return  1.273239545 / (tau * (1.0 + alpha(zeta))); }
            static constexpr double k2(double tau, double zeta)
                { return alpha(zeta) * k1(tau, zeta) * k1(tau, zeta); }
            // End-to-end loop gain including intermediate scaling:
            //  * Input scaling: 1 second offset = SUBNS_PER_SEC LSBs.
            //  * T0 compensation: Multiply by assumed T0 = 1 sec.
            //  * NCO scaling: 1 LSB = ref_scale seconds per second.
            //  * Cycles to radians: Effective gain = 1 / (2*pi).
            //  * Output scaling: Divide final output by 2^SCALE.
            static constexpr double fw_gain(double ref_scale)
                { return double(satcat5::ptp::SUBNS_PER_SEC)
                       * double(satcat5::ptp::NSEC_PER_SEC)
                       * ref_scale / 6.28318530717958647693
                       / double(1LL << SCALE); }
            // Max slew rate of 10 msec per second, converted to LSBs.
            static constexpr double slew_limit(double ref_scale)
                { return 0.010 / ref_scale; }

            friend satcat5::ptp::TrackingController;
            u64 kp;     // Proportional coefficient (LSB per subns)
            u64 ki;     // Integral coefficient (LSB per subns)
            u64 ymax;   // Maximum steady-state output (LSB)
        };

        // Fixed-point loop-filter implementation.
        class TrackingController {
        public:
            // Constructor links to a specific TrackingClock target
            // and sets loop bandwidth, which can be changed later.
            explicit TrackingController(
                satcat5::ptp::TrackingClock* clk,
                const satcat5::ptp::TrackingCoeff& coeff);

            // Reconfigure tracking-loop bandwidth.
            void reconfigure(const satcat5::ptp::TrackingCoeff& coeff);

            // Reset tracking filter and begin free-wheeling.
            void reset();

            // Update filter state with a new measurement from the PTP client.
            // Specify the local message-received timestamp (rxtime) and the
            // measured clock offset (delta = remote - local).
            void update(
                const satcat5::ptp::Time& rxtime,
                const satcat5::ptp::Time& delta);

            // Enable debugging direct to network interface.
            inline void set_debug(satcat5::net::Address* addr)
                { m_debug = addr; }

            // Set maximum size of internal accumulators.
            typedef satcat5::util::uint128_t Accumulator;

        protected:
            // Run filter one timestep.
            void filter(u32 elapsed_nsec, s64 delta_subns);

            satcat5::ptp::TrackingClock* const m_clk;
            satcat5::ptp::TrackingCoeff m_coeff;
            satcat5::net::Address* m_debug;
            satcat5::ptp::Time m_last_rcvd;
            satcat5::util::Prng m_prng;
            satcat5::ptp::TrackingController::Accumulator m_accum;
        };
    }
}
