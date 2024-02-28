//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Chainable filters for use with ptp::TrackingController.
//
// This file defines various "filter" objects that can be chained together
// to implement the ptp::TrackingController loop-filter.  Filters can be
// applied before or after the primary PID loop defined in that class,
// which is usually "ptp::ControllerPI".
//
// The optimal filter configuration depends on the quality and refresh rate
// of the upstream source.  A median-filter of order 3-5 is recommend for
// most applications to remove outliers.  Additional filtering can mitigate
// measurement noise, at the cost of a slower loop response.  Excessive
// filter delays can cause tracking loops to become unstable.
//
// At runtime, all filters in this file use fixed-point arithmetic.
// Floating-point is only used for one-time calculations during build.
//
// Most filters are configurable at runtime, but certain upper limits must
// be set at build-time to avoid using excessive amounts of memory.  Where
// practical, template parameters are used to make these limits adjustable,
// since filter requirements vary widely by application.
//

#pragma once

#include <satcat5/list.h>
#include <satcat5/ptp_time.h>
#include <satcat5/wide_integer.h>

namespace satcat5 {
    namespace ptp {
        // Define the basic input/output chaining functionality.
        class Filter {
        public:
            // Flush previous inputs and reset to a neutral state.
            virtual void reset() = 0;

            // Optional handler for fast-acquisition; override if required.
            // Upstream controller provides estimated rate (i.e., rise/run).
            // The "elapsed_usec" parameter will be between 10^5 and 10^7.
            virtual void rate(s64 delta_subns, u32 elapsed_usec) {}

            // Method called for each new input sample.
            // Input or output of INT64_MAX indicates the sample should be
            // discarded.  Otherwise, return the resulting output sample.
            // The "elapsed_usec" parameter will be between 10^3 and 10^6.
            virtual s64 update(s64 next, u32 elapsed_usec) = 0;

        protected:
            // Private constructor and destructor.
            Filter() : m_next(0) {}
            ~Filter() {}

            // Linked-list of chained filter objects.
            friend satcat5::util::ListCore;
            satcat5::ptp::Filter* m_next;
        };

        // A sliding-window circular buffer, retaining the last N samples.
        template<typename T, unsigned MAX_WINDOW>
        class SlidingWindow final {
        public:
            SlidingWindow() : m_wridx(0), m_window{0} {}
            ~SlidingWindow() {}

            // Copy the N most recent samples from the working buffer.
            // (The last index of the output array is the most recent sample.)
            void read(T* dst, unsigned count) const {
                if (m_wridx >= count) {
                    memcpy(dst, m_window + m_wridx - count, count*sizeof(T));
                } else {
                    unsigned wrap = count - m_wridx;
                    memcpy(dst, m_window + MAX_WINDOW - wrap, wrap*sizeof(T));
                    memcpy(dst + wrap, m_window, m_wridx*sizeof(T));
                }
            }

            // Write one new sample to the working buffer.
            void push(const T& next) {
                m_window[m_wridx] = next;
                if (++m_wridx >= MAX_WINDOW) m_wridx = 0;
            }

            void reset() {
                memset(m_window, 0, MAX_WINDOW * sizeof(T));
            }

        protected:
            unsigned m_wridx;
            T m_window[MAX_WINDOW];
        };

        // Coarse frequency adjustment:
        //  * Input scaling: 1 usec offset = SUBNS_PER_USEC LSBs.
        //  * Frequency calculation: Scale by 1 / interval_usec.
        //  * NCO scaling: 1 LSB = ref_scale seconds per second.
        // (Note: Result is typically between 2^7 and 2^28.)
        constexpr double freq_gain(double ref_scale)
            { return 1.0 / (double(satcat5::ptp::SUBNS_PER_USEC) * ref_scale); }

        // Max slew rate of 10 msec per second, converted to LSBs.
        // (Note: Result is typically between 2^33 and 2^54.)
        constexpr double slew_limit(double ref_scale)
            { return 0.010 / ref_scale; }

        // Low-level functions implemented outside the template classes.
        s64 boxcar_filter(const s64* data, unsigned order);
        s64 median_filter(s64* data, unsigned samps);

        // Amplitude-based outlier rejection.  Iteratively estimate RMS power
        // of the input, then reject outliers based on that estimate.
        class AmplitudeReject : public satcat5::ptp::Filter {
        public:
            explicit AmplitudeReject(unsigned tau_msec = 10000);

            // Accessors for settings and internal state.
            inline s64 get_mean() const         {return m_mean;}
            inline u64 get_sigma() const        {return m_sigma;}
            inline void set_min(u64 min_subns)  {m_min = min_subns;}
            inline void set_tau(u32 tau_msec)   {m_tau_usec = 1000*tau_msec;}

            // Required API from ptp::Filter.
            void reset() override;
            s64 update(s64 next, u32 elapsed_usec) override;

        protected:
            s64 m_mean;
            u64 m_sigma;
            u64 m_min;
            u32 m_tau_usec;
        };

        // An FIR low-pass filter using "boxcar" averaging over 2^N samples.
        // Note: Order 0 is a simple passthrough.
        template<unsigned MAX_ORDER>
        class BoxcarFilter : public satcat5::ptp::Filter {
        public:
            explicit BoxcarFilter(unsigned order = MAX_ORDER)
                : m_order(0) {set_order(order);}

            inline void set_order(unsigned x)
                { if (x <= MAX_ORDER) m_order = x; }

            void reset() override
                { m_window.reset(); }

            s64 update(s64 next, u32 elapsed_usec) override {
                if (next == INT64_MAX) return INT64_MAX;
                s64 temp[MAX_WINDOW];
                m_window.push(next);
                m_window.read(temp, 1u << m_order);
                return satcat5::ptp::boxcar_filter(temp, m_order);
            }

        protected:
            static constexpr unsigned MAX_WINDOW = 1u << MAX_ORDER;
            unsigned m_order;
            satcat5::ptp::SlidingWindow<s64, MAX_WINDOW> m_window;
        };

        // A median filter for an odd number of elements.
        // Note: Order 1 is a simple passthrough.
        template<unsigned MAX_ORDER>
        class MedianFilter : public satcat5::ptp::Filter {
        public:
            explicit MedianFilter(unsigned order = MAX_ORDER)
                : m_order(0) {set_order(order);}

            inline void set_order(unsigned x)
                { if (x <= MAX_ORDER) m_order = x|1; }

            void reset() override
                { m_window.reset(); }

            s64 update(s64 next, u32 elapsed_usec) override {
                if (next == INT64_MAX) return INT64_MAX;
                s64 temp[MAX_ORDER];
                m_window.push(next);
                m_window.read(temp, m_order);
                return satcat5::ptp::median_filter(temp, m_order);
            }

        protected:
            unsigned m_order;
            satcat5::ptp::SlidingWindow<s64, MAX_ORDER|1> m_window;
        };

        // Loop-filter coefficients for use with the "ControllerPI" class.
        // All floating-point calculations can be run at build-time.
        //
        // The process requires three arguments:
        // * "ref_scale" is a unitless quantity that indicates the scaling
        //   factor for "ptp::TrackingClock::clock_rate(...)".  It is measured
        //   in seconds-per-second per LSB, i.e., a value of X indicates that
        //   an offset of one LSB, sustained for one second, shifts RefClock
        //   by a total of X seconds.  For best results, this quantity should
        //   be greater than 10^-16 and less than 10^-10.  For less precise
        //   clocks (i.e., larger ref_scale), use RefDither.
        // * "tau_secs" is the desired filter time constant in seconds.
        //   A time constant of about 5.0 seconds is typical.
        // * "damping" is the unitless damping ratio, zeta.
        //   Default 0.707 is slightly underdamped for reduced settling time.
        //
        // See also: Stephens & Thomas, "Controlled-root formulation for
        //  digital phase-locked loops", IEEE Transactions on Aerospace and
        //  Electronic Systems 1995, doi: 10.1109/7.366295.
        // https://ieeexplore.ieee.org/abstract/document/366295
        struct CoeffPI {
        public:
            // Calculate tracking-loop coefficients.
            constexpr CoeffPI(
                double ref_scale, double tau_secs, double damping = 0.707)
                : kp(satcat5::util::round_u64z(k1(tau_secs, damping) / fw_gain(ref_scale)))
                , ki(satcat5::util::round_u64z(k2(tau_secs, damping) / fw_gain(ref_scale)))
                , kf(satcat5::util::round_u64z(freq_gain(ref_scale)))
                , ymax(satcat5::util::round_u64z(slew_limit(ref_scale)))
                {} // No other initialization required.

            // Are all coefficients large enough to mitigate rounding error?
            bool ok() const {return (kp > 7) && (ki > 7) && (kf > 7);}

            // Fixed-point scaling of each coefficient by 2^-N.
            // Optimized for time constants circa 1-3600 seconds.
            static constexpr unsigned SCALE = 60;

        protected:
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
                       * double(satcat5::ptp::USEC_PER_SEC)
                       * ref_scale / 6.28318530717958647693
                       / satcat5::util::pow2d(SCALE); }

            friend satcat5::ptp::ControllerPI;
            u64 kp;     // Proportional coefficient (LSB per subns)
            u64 ki;     // Integral coefficient (LSB per subns)
            u64 kf;     // Coarse frequency adjustment (LSB per subns/usec)
            u64 ymax;   // Maximum steady-state output (LSB)
        };

        // Loop-filter for a proportional-integral (PI) controller.
        // This 2nd-order linear filter can accurately track a steady-state
        // frequency offset.  It is the recommended option for most users.
        class ControllerPI : public satcat5::ptp::Filter {
        public:
            // Constructor sets loop bandwidth, which can be changed later.
            explicit ControllerPI(const satcat5::ptp::CoeffPI& coeff);

            // Adjust tracking-loop bandwidth.
            void set_coeff(const satcat5::ptp::CoeffPI& coeff);

            // Required API from ptp::Filter.
            void reset() override;
            void rate(s64 delta, u32 elapsed_usec) override;
            s64 update(s64 next, u32 elapsed_usec) override;

        protected:
            // Internal state.
            satcat5::ptp::CoeffPI m_coeff;
            satcat5::util::int128_t m_accum;
        };

        // Loop-filter coefficients for use with the "ControllerPII" class.
        // All floating-point calculations can be run at build-time.
        // (This is also based on Stephens & Thomas 1995.)
        struct CoeffPII {
        public:
            // Calculate tracking-loop coefficients.
            constexpr CoeffPII(
                double ref_scale, double tau_secs)
                : kp(satcat5::util::round_u64z(k1(tau_secs) / fw_gain(ref_scale)))
                , ki(satcat5::util::round_u64z(k2(tau_secs) / fw_gain(ref_scale)))
                , kr(satcat5::util::round_u64z(kratio(tau_secs)))
                , kf(satcat5::util::round_u64z(freq_gain(ref_scale)))
                , ymax(satcat5::util::round_u64z(slew_limit(ref_scale)))
                {} // No other initialization required.

            // Are all coefficients large enough to mitigate rounding error?
            bool ok() const {return (kp > 7) && (ki > 7) && (kr > 7) && (kf > 7);}

            // Fixed-point scaling of each coefficient by 2^-N.
            // Optimized for time constants circa 1-3600 seconds.
            static constexpr unsigned SCALE1 = 70;
            static constexpr unsigned SCALE2 = 64;
            static constexpr unsigned SCALE = SCALE1 + SCALE2;

        protected:
            // "Standard underdamped" K1, K2, and K2 from Stephens & Thomas Table III.
            // Note: Omit scaling by T0; compensate for this at runtime.
            static constexpr double k1(double tau)
                { return 0.830373616 / tau; }   // i.e., 60 / 23pi
            static constexpr double k2(double tau)
                { return (4.0/9.0) * k1(tau) * k1(tau); }
            static constexpr double k3(double tau)
                { return (2.0/27.0) * k1(tau) * k1(tau) * k1(tau); }
            // Ratio of K3 / K2, used for nested-accumulator updates.
            static constexpr double kratio(double tau)
                { return k3(tau) / k2(tau) * satcat5::util::pow2d(SCALE2)
                       / double(satcat5::ptp::USEC_PER_SEC); }
            // End-to-end loop gain for including intermediate scaling:
            //  * Input scaling: 1 second offset = SUBNS_PER_SEC LSBs.
            //  * T0 compensation: Multiply by assumed T0 = 1 sec.
            //  * NCO scaling: 1 LSB = ref_scale seconds per second.
            //  * Cycles to radians: Effective gain = 1 / (2*pi).
            //  * Output scaling: Divide final output by 2^SCALE1.
            static constexpr double fw_gain(double ref_scale)
                { return double(satcat5::ptp::SUBNS_PER_SEC)
                       * double(satcat5::ptp::USEC_PER_SEC)
                       * ref_scale / 6.28318530717958647693
                       / satcat5::util::pow2d(SCALE1); }

            friend satcat5::ptp::ControllerPII;
            u64 kp;     // Proportional coefficient (LSB per subns)
            u64 ki;     // Integral coefficient (LSB per subns)
            u64 kr;     // Double-integral coefficient (K3 / K2)
            u64 kf;     // Coarse frequency adjustment (LSB per subns/usec)
            u64 ymax;   // Maximum steady-state output (LSB)
        };

        // Loop-filter for a proportional-integral (PI) controller.
        // This 3rd-order linear filter can accurately track a steady-state
        // frequency chirp.  This improves performance for some oscillators.
        class ControllerPII : public satcat5::ptp::Filter {
        public:
            // Constructor sets loop bandwidth, which can be changed later.
            explicit ControllerPII(const satcat5::ptp::CoeffPII& coeff);

            // Adjust tracking-loop bandwidth.
            void set_coeff(const satcat5::ptp::CoeffPII& coeff);

            // Required API from ptp::Filter.
            void reset() override;
            void rate(s64 delta, u32 elapsed_usec) override;
            s64 update(s64 next, u32 elapsed_usec) override;

        protected:
            // Internal state.
            satcat5::ptp::CoeffPII m_coeff;
            satcat5::util::int128_t m_accum1;
            satcat5::util::int256_t m_accum2;
        };

        // Loop-filter coefficients for use with the "ControllerLR" class.
        // All floating-point calculations can be run at build-time.
        struct CoeffLR {
        public:
            // Calculate tracking-loop coefficients.
            constexpr CoeffLR(double ref_scale, double tau_secs)
                : ki(satcat5::util::round_u64z(ki_gain(ref_scale) / tau_secs))
                , kf(satcat5::util::round_u64z(ki_gain(ref_scale)))
                , kw(satcat5::util::round_u64z(kw_gain() * 2.0 / tau_secs))
                , ymax(satcat5::util::round_u64z(slew_limit(ref_scale)))
                {} // No other initialization required.

            // Are all coefficients large enough to mitigate rounding error?
            bool ok() const {return (ki > 7) && (kf > 7) && (kw > 7);}

            // Fixed-point scaling of each coefficient by 2^-N.
            // Optimized for time constants circa 1-3600 seconds.
            static constexpr unsigned SCALE1 = 32;
            static constexpr unsigned SCALE2 = 32;
            static constexpr unsigned SCALE = SCALE1 + SCALE2;

        protected:
            static constexpr double ki_gain(double ref_scale)
                { return satcat5::util::pow2d(SCALE2)
                       / double(satcat5::ptp::SUBNS_PER_USEC) / ref_scale; }
            static constexpr double kw_gain()
                { return satcat5::util::pow2d(SCALE1 + SCALE2)
                       / double(satcat5::ptp::USEC_PER_SEC); }

            friend class satcat5::ptp::ControllerLR_Inner;
            u64 ki;     // Integral coefficient (LSB per subns)
            u64 kf;     // Coarse frequency adjustment (LSB per subns/usec)
            u64 kw;     // Intercept scaling factor (LSB per usec)
            u64 ymax;   // Maximum steady-state output (LSB)
        };

        // Helper class for "ControllerLR" is never used directly.
        // (It minimizes the amount of code in the class-template wrapper.)
        class ControllerLR_Inner : public satcat5::ptp::Filter {
        public:
            // Adjust loop bandwidth.
            void set_coeff(const satcat5::ptp::CoeffLR& coeff);

            // Partial API from ptp::Filter.
            void rate(s64 delta, u32 elapsed_usec) override;

        protected:
            // Private constructor and destructor.
            ControllerLR_Inner(const satcat5::ptp::CoeffLR& coeff, unsigned window);
            ~ControllerLR_Inner() {}

            // Signal processing functions.
            s64 update_inner(const u32* dt, const s64* y);

            // Internal state, not including sliding-window buffers.
            satcat5::ptp::CoeffLR m_coeff;
            satcat5::util::int128_t m_accum;
            unsigned m_window;
        };

        // Loop-filter for a linear-regression (LR) controller.
        // This filter uses linear regression to estimate phase and frequency
        // offsets over a short window, then applies an IIR filter to track
        // that piecewise-linear estimate with a controlled time-constant.
        template<unsigned MAX_WINDOW>
        class ControllerLR : public satcat5::ptp::ControllerLR_Inner {
        public:
            // Constructor sets loop bandwidth, which can be changed later.
            explicit ControllerLR(const satcat5::ptp::CoeffLR& coeff)
                : satcat5::ptp::ControllerLR_Inner(coeff, MAX_WINDOW)
                , m_count(0), m_elapsed(0) {}
            static_assert(MAX_WINDOW >= 2, "MAX_WINDOW must be at least 2.");

            // Adjust window-size.
            // Also note "set_coeff(...)" inherited from parent.
            void set_window(unsigned window) {
                if (2 <= window && window <= MAX_WINDOW) m_window = window;
            }

            // Remaining API from ptp::Filter.
            void reset() override {
                m_dly.reset();
                m_dat.reset();
                m_accum = satcat5::util::INT128_ZERO;
            }

            s64 update(s64 next, u32 elapsed_usec) override {
                // Push valid samples into the sliding-window buffers.
                // (Elapsed time still increments even if we drop a sample.)
                m_elapsed += elapsed_usec;
                if (next == INT64_MAX) return INT64_MAX;
                m_dly.push(m_elapsed);
                m_dat.push(next);
                m_elapsed = 0;
                // Attempt to read a full window of samples...
                if (m_count < MAX_WINDOW) ++m_count;
                if (m_count < m_window) return INT64_MAX;
                u32 temp_dly[MAX_WINDOW];   m_dly.read(temp_dly, m_window);
                s64 temp_dat[MAX_WINDOW];   m_dat.read(temp_dat, m_window);
                // Proceed with linear-regression processing.
                return update_inner(temp_dly, temp_dat);
            }

        protected:
            unsigned m_count;
            u32 m_elapsed;
            satcat5::ptp::SlidingWindow<u32, MAX_WINDOW> m_dly;
            satcat5::ptp::SlidingWindow<s64, MAX_WINDOW> m_dat;
        };
    }
}
