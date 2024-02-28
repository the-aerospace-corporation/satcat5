//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ptp_filters.h>
#include <satcat5/ptp_time.h>

using satcat5::ptp::boxcar_filter;
using satcat5::ptp::median_filter;
using satcat5::ptp::AmplitudeReject;
using satcat5::ptp::CoeffLR;
using satcat5::ptp::CoeffPI;
using satcat5::ptp::CoeffPII;
using satcat5::ptp::ControllerLR_Inner;
using satcat5::ptp::ControllerPI;
using satcat5::ptp::ControllerPII;
using satcat5::ptp::SUBNS_PER_NSEC;
using satcat5::util::INT128_ZERO;
using satcat5::util::int128_t;
using satcat5::util::INT256_ZERO;
using satcat5::util::int256_t;
using satcat5::util::uint128_t;

// Enable additional diagnostics? (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

// Maximum unrolled filter size for ptp::MedianFilter.
// (Reducing this may help decrease code-size in some cases.)
#ifndef SATCAT5_PTP_UNROLL_MEDIAN
#define SATCAT5_PTP_UNROLL_MEDIAN 9
#endif

// Enable psuedorandom dither?
#ifndef SATCAT5_PTRK_DITHER
#define SATCAT5_PTRK_DITHER 1
#endif

// Dither allows averaging over time for sub-LSB resolution.
static inline u32 next_dither() {
    #if SATCAT5_PTRK_DITHER
        static satcat5::util::Prng prng(0xDEADBEEF);
        return prng.next();
    #else
        return 0;
    #endif
}

template <class T = int128_t>
static inline T big_dither(unsigned scale) {
    T dither(next_dither());
    if (scale > 32) dither <<= (scale - 32);
    if (scale < 32) dither >>= (32 - scale);
    return dither;
}

template <class T>
static inline s64 wide_output(const T& x, unsigned scale) {
    return s64((x + big_dither<T>(scale)) >> scale);
}

s64 satcat5::ptp::boxcar_filter(const s64* data, unsigned order) {
    // Passthrough mode?
    if (order == 0) return data[0];
    unsigned samps = 1u << order;

    // Equal-weight sum over the last N samples.
    // (Avoid sub-LSB bias using pseudorandom dither.)
    int128_t sum(next_dither() & u32(samps-1));
    for (unsigned a = 0 ; a < samps ; ++a) {
        sum += int128_t(data[a]);
    }
    return s64(sum >> order);
}

static inline void sort2(s64& a, s64&b) {
    if (a > b) {satcat5::util::swap_ref(a, b);}
}

s64 satcat5::ptp::median_filter(s64* tmp, unsigned samps) {
    // Passthrough mode?
    if (samps <= 1) return tmp[0];

    // Recalculate the median over the last N samples.
    // Algorithm is a hand-pruned sorting network for each supported size.
    // See "optmed" method: http://ndevilla.free.fr/median/median/index.html
    if (SATCAT5_PTP_UNROLL_MEDIAN >= 3 && samps == 3) {
        sort2(tmp[0], tmp[1]); sort2(tmp[1], tmp[2]);
        sort2(tmp[0], tmp[1]); return tmp[1];
    } else if (SATCAT5_PTP_UNROLL_MEDIAN >= 5 && samps == 5) {
        sort2(tmp[0], tmp[1]); sort2(tmp[3], tmp[4]);
        sort2(tmp[0], tmp[3]); sort2(tmp[1], tmp[4]);
        sort2(tmp[1], tmp[2]); sort2(tmp[2], tmp[3]);
        sort2(tmp[1], tmp[2]); return tmp[2];
    } else if (SATCAT5_PTP_UNROLL_MEDIAN >= 7 && samps == 7) {
        sort2(tmp[0], tmp[5]); sort2(tmp[0], tmp[3]);
        sort2(tmp[1], tmp[6]); sort2(tmp[2], tmp[4]);
        sort2(tmp[0], tmp[1]); sort2(tmp[3], tmp[5]);
        sort2(tmp[2], tmp[6]); sort2(tmp[2], tmp[3]);
        sort2(tmp[3], tmp[6]); sort2(tmp[4], tmp[5]);
        sort2(tmp[1], tmp[4]); sort2(tmp[1], tmp[3]);
        sort2(tmp[3], tmp[4]); return tmp[3];
    } else if (SATCAT5_PTP_UNROLL_MEDIAN >= 9 && samps == 9) {
        sort2(tmp[1], tmp[2]); sort2(tmp[4], tmp[5]);
        sort2(tmp[7], tmp[8]); sort2(tmp[0], tmp[1]);
        sort2(tmp[3], tmp[4]); sort2(tmp[6], tmp[7]);
        sort2(tmp[1], tmp[2]); sort2(tmp[4], tmp[5]);
        sort2(tmp[7], tmp[8]); sort2(tmp[0], tmp[3]);
        sort2(tmp[5], tmp[8]); sort2(tmp[4], tmp[7]);
        sort2(tmp[3], tmp[6]); sort2(tmp[1], tmp[4]);
        sort2(tmp[2], tmp[5]); sort2(tmp[4], tmp[7]);
        sort2(tmp[4], tmp[2]); sort2(tmp[6], tmp[4]);
        sort2(tmp[4], tmp[2]); return tmp[4];
    } else {
        // For windows above the hand-coded limit, use regular sort.
        satcat5::util::sort(tmp, tmp + samps);
        return tmp[samps / 2];
    }
}

AmplitudeReject::AmplitudeReject(unsigned tau_msec)
    : m_mean(0)
    , m_sigma(UINT64_MAX/2)
    , m_min(SUBNS_PER_NSEC)
    , m_tau_usec(1000*tau_msec)
{
    // Nothing else to initialize.
}

void AmplitudeReject::reset() {
    m_mean = 0;
    m_sigma = UINT64_MAX/2;
}

s64 AmplitudeReject::update(s64 next, u32 elapsed_usec) {
    // Ignore inputs that have already been rejected.
    if (next == INT64_MAX) return INT64_MAX;

    // Define various local constants...
    const int128_t MIN128(m_min);
    const int128_t MAX128(UINT64_MAX/2);
    const int128_t SQRTPI2(u64(5382943231ull));  // 2^32 * sqrt(pi/2)

    // Calculate update rate for the fixed-point IIR filters.
    // Small-signal approximation for t << tau: k = 2^32 * t / tau
    elapsed_usec = satcat5::util::min_u32(elapsed_usec, m_tau_usec/2);
    uint128_t tau(elapsed_usec, 0);             // Range 0..2^51
    tau /= uint128_t(m_tau_usec);               // Range 0..2^31

    // Calculate difference from the mean (may overflow s64).
    int128_t diff(next);                        // Range +/- 2^63
    diff -= int128_t(m_mean);                   // Range +/- 2^64

    // IIR filter to estimate the mean.
    m_mean += s64((diff * tau + big_dither(32)) >> 32u);

    // Calculate the scaled absolute difference.  If the input is normally
    // distributed, then the expected absolute difference is sigma*sqrt(2/pi).
    // See also: https://en.wikipedia.org/wiki/Folded_normal_distribution
    int128_t adiff = (SQRTPI2 * diff.abs() + big_dither(32)) >> 32u;
    adiff -= int128_t(m_sigma);                 // Range +/- 2^65

    // IIR filter to estimate the standard deviation.
    // (Do not allow sigma to fall below designated minimum.)
    int128_t sigma(m_sigma);                    // Range 0..2^63
    sigma += (adiff * tau + big_dither(32)) >> 32u;
    if (sigma < MIN128) sigma = MIN128;
    if (sigma > MAX128) sigma = MAX128;
    m_sigma = u64(sigma);                       // Range 0..2^63

    // Does this sample fall within 6-sigma of the mean?
    int128_t thresh(m_sigma); thresh *= int128_t(u32(6));
    return (diff.abs() < thresh) ? next : INT64_MAX;
}

ControllerPI::ControllerPI(const CoeffPI& coeff)
    : m_coeff(coeff)
    , m_accum(INT128_ZERO)
{
    set_coeff(coeff);   // For error-reporting.
}

void ControllerPI::set_coeff(const CoeffPI& coeff) {
    m_coeff = coeff;
    if (DEBUG_VERBOSE > 0) {
        auto level = coeff.ok() ? log::DEBUG : log::ERROR;
        log::Log(level, "ControllerPI: Config")
            .write10(m_coeff.kp)
            .write10(m_coeff.ki)
            .write10(m_coeff.kf)
            .write10(m_coeff.ymax);
    } else if (!coeff.ok()) {
        log::Log(log::ERROR, "ControllerPI: Bad config.");
    }
}

void ControllerPI::reset() {
    m_accum = INT128_ZERO;
}

void ControllerPI::rate(s64 delta_subns, u32 elapsed_usec) {
    // Limit input to a sensible range...
    delta_subns = satcat5::util::clamp(delta_subns, 10 * SUBNS_PER_MSEC);
    // After division, scaling factor is typically 2^36 to 2^44.
    u64 scale = (1ull << m_coeff.SCALE) / elapsed_usec;
    int128_t rate(delta_subns);                 // Range +/- 2^40
    rate *= int128_t(m_coeff.kf);               // Range +/- 2^68
    rate *= int128_t(scale);                    // Range +/- 2^112
    m_accum += rate;
}

s64 ControllerPI::update(s64 delta_subns, u32 elapsed_usec) {
    // Ignore invalid inputs and clamp to a sensible limit.
    if (delta_subns == INT64_MAX) return INT64_MAX;
    delta_subns = satcat5::util::clamp(delta_subns, SUBNS_PER_MSEC);

    // Convert inputs to extra-wide integers for more dynamic range,
    // then multiply by the KI and KP loop-gain coefficients.
    int128_t delta_i(delta_subns);              // Range +/- 2^36
    int128_t delta_p(delta_subns);              // Range +/- 2^36
    delta_i *= int128_t(m_coeff.ki);            // Range +/- 2^100
    delta_p *= int128_t(m_coeff.kp);            // Range +/- 2^100

    // Compensate for changes to the effective sample interval T0, using
    // most recent elapsed time as a proxy for future sample intervals.
    //  * Output to NCO is a rate, held and accumulated for T0 seconds.
    //    Therefore, outputs must be scaled by 1/T0 to compensate.
    //  * I gain is missing implicit T0^2, so net scaling by T0.
    //  * P gain is missing implicit T0, so net scaling is unity.
    delta_i *= int128_t(elapsed_usec);          // Range +/- 2^120
    delta_p *= int128_t(USEC_PER_SEC);          // Range +/- 2^120

    // Update the accumulator.  Calculating sum(KI * phi) instead of
    // KI * sum(phi) ensures continuity after bandwidth changes.
    m_accum += delta_i;                         // Range +/- 2^121

    // Clamp accumulator term to +/- ymax, to mitigate windup.
    int128_t ymax(m_coeff.ymax);                // Range 2^33..2^54
    m_accum.clamp(ymax << m_coeff.SCALE);       // Range +/- 2^114

    // Tracking output is the sum of all filter terms.
    // (Sum up to +/- 2^121, output up to +/- 2^61.)
    return wide_output(m_accum + delta_p, m_coeff.SCALE);
}

ControllerPII::ControllerPII(const CoeffPII& coeff)
    : m_coeff(coeff)
    , m_accum1(INT128_ZERO)
    , m_accum2(INT256_ZERO)
{
    set_coeff(coeff);   // For error-reporting.
}

void ControllerPII::set_coeff(const CoeffPII& coeff) {
    m_coeff = coeff;
    if (DEBUG_VERBOSE > 0) {
        auto level = coeff.ok() ? log::DEBUG : log::ERROR;
        log::Log(level, "ControllerPII: Config")
            .write10(m_coeff.kp)
            .write10(m_coeff.ki)
            .write10(m_coeff.kr)
            .write10(m_coeff.kf)
            .write10(m_coeff.ymax);
    } else if (!coeff.ok()) {
        log::Log(log::ERROR, "ControllerPII: Bad config.");
    }
}

void ControllerPII::reset() {
    m_accum1 = INT128_ZERO;
    m_accum2 = INT256_ZERO;
}

void ControllerPII::rate(s64 delta_subns, u32 elapsed_usec) {
    // Limit input to a sensible range...
    delta_subns = satcat5::util::clamp(delta_subns, 10 * SUBNS_PER_MSEC);
    int256_t rate(delta_subns);                 // Range +/- 2^40
    rate <<= m_coeff.SCALE;                     // Range +/- 2^174
    rate *= int256_t(m_coeff.kf);               // Range +/- 2^202
    rate /= int256_t(elapsed_usec);             // Range +/- 2^226
    rate.clamp(int256_t(m_coeff.ymax) << m_coeff.SCALE);
    m_accum2 += rate;                           // Range +/- 2^188
}

s64 ControllerPII::update(s64 delta_subns, u32 elapsed_usec) {
    // Ignore invalid inputs and clamp to a sensible limit.
    if (delta_subns == INT64_MAX) return INT64_MAX;
    delta_subns = satcat5::util::clamp(delta_subns, SUBNS_PER_MSEC);

    // Convert inputs to extra-wide integers for more dynamic range,
    // then multiply by the KI and KP loop-gain coefficients.
    int128_t delta_i(delta_subns);              // Range +/- 2^36
    int128_t delta_p(delta_subns);              // Range +/- 2^36
    delta_i *= int128_t(m_coeff.ki);            // Range +/- 2^100
    delta_p *= int128_t(m_coeff.kp);            // Range +/- 2^100

    // Compensate for changes to the effective sample interval T0, using
    // most recent elapsed time as a proxy for future sample intervals.
    //  * Output to NCO is a rate, held and accumulated for T0 seconds.
    //    Therefore, outputs must be scaled by 1/T0 to compensate.
    //  * J gain is missing implicit T0^3, so net scaling by T0^2.
    //  * I gain is missing implicit T0^2, so net scaling by T0.
    //  * P gain is missing implicit T0, so net scaling is unity.
    delta_i *= int128_t(elapsed_usec);          // Range +/- 2^120
    delta_p *= int128_t(USEC_PER_SEC);          // Range +/- 2^120

    // Update the primary accumulator, i.e., sum(K2 * phi).
    // As with ControllerPI, precalculate gain to ensure continuity.
    int128_t ymax1(m_coeff.ymax);               // Range 2^33..2^54
    m_accum1 += delta_i;                        // Range +/- 2^125
    m_accum1.clamp(ymax1 << m_coeff.SCALE1);    // Range +/- 2^124

    // Update the secondary accumulator, i.e.,  sum(sum(K3 * phi)).
    // To avoid using a third accumulator, re-scale the primary by K3 / K2.
    int256_t ymax2(m_coeff.ymax);               // Range 2^33..2^54
    int256_t delta_r(m_accum1);                 // Range +/- 2^124
    delta_r *= int256_t(m_coeff.kr);            // Range +/- 2^188
    delta_r *= int256_t(elapsed_usec);          // Range +/- 2^208
    m_accum2 += delta_r;                        // Range +/- 2^209
    m_accum2.clamp(ymax2 << m_coeff.SCALE);     // Range +/- 2^188

    // Tracking output is the sum of all filter terms.
    int128_t delta_ii((m_accum2 + big_dither(m_coeff.SCALE2)) >> m_coeff.SCALE2);
    return wide_output(m_accum1 + delta_ii + delta_p, m_coeff.SCALE1);
}

ControllerLR_Inner::ControllerLR_Inner(const CoeffLR& coeff, unsigned window)
    : m_coeff(coeff), m_accum(INT128_ZERO), m_window(window)
{
    set_coeff(coeff);   // For error-reporting.
}

void ControllerLR_Inner::set_coeff(const CoeffLR& coeff)
{
    m_coeff = coeff;
    if (DEBUG_VERBOSE > 0) {
        auto level = coeff.ok() ? log::DEBUG : log::ERROR;
        log::Log(level, "ControllerLR: Config")
            .write10(m_coeff.ki)
            .write10(m_coeff.kf)
            .write10(m_coeff.kw);
    } else if (!coeff.ok()) {
        log::Log(log::ERROR, "ControllerLR: Bad config.");
    }
}

void ControllerLR_Inner::rate(s64 delta_subns, u32 elapsed_usec) {
    // Limit input to a sensible range...
    delta_subns = satcat5::util::clamp(delta_subns, 10 * SUBNS_PER_MSEC);
    int128_t rate(delta_subns);
    rate <<= m_coeff.SCALE1;
    rate *= int128_t(m_coeff.kf);
    rate /= int128_t(elapsed_usec);
    m_accum += rate;
}

s64 ControllerLR_Inner::update_inner(const u32* dt, const s64* y) {
    // Convert incremental timesteps to cumulative time,
    // using t = 0 for the most recent input sample.
    s64 x[m_window] = {0};
    for (unsigned n = m_window-1 ; n != 0 ; --n) {
        x[n-1] = x[n] - dt[n];
    }

    // Calculate the sum of each input vector.
    int128_t sum_x = INT128_ZERO, sum_y = INT128_ZERO;
    for (unsigned n = 0 ; n < m_window ; ++n) {
        sum_x += int128_t(x[n]);
        sum_y += int128_t(y[n]);
    }

    // Calculate the covariance terms:
    //  cov_xx = sum(dx * dx) and cov_xy = sum(dx * dy),
    //  where dx[n] = x[n] - mean(x) and dy[n] = y[n] - mean(y).
    // To avoid loss of precision, don't divide by the window size:
    //  cov_xx * N^2 = sum(dx' * dx'), where dx' = N*x - sum(x).
    const int128_t window((u32)m_window);
    int256_t cov_xx(INT256_ZERO), cov_xy(INT256_ZERO);
    for (unsigned n = 0 ; n < m_window ; ++n) {
        int256_t dx(int128_t(x[n]) * window - sum_x);
        int256_t dy(int128_t(y[n]) * window - sum_y);
        cov_xx += dx * dx;
        cov_xy += dx * dy;
    }

    // Discard degenerate cases where timestamps are too close together.
    constexpr u64 MIN_SPAN_USEC = 2000;
    constexpr u64 MIN_COV = MIN_SPAN_USEC * MIN_SPAN_USEC / 12;
    int256_t min_cov_xx(MIN_COV * m_window);
    if (cov_xx < min_cov_xx) return INT64_MIN;

    // Calculate slope and intercept by linear regression.
    // https://en.wikipedia.org/wiki/Simple_linear_regression
    int128_t beta(((cov_xy << m_coeff.SCALE1) + (cov_xx >> 1)) / cov_xx);
    int128_t xbeta((beta * sum_x + big_dither(m_coeff.SCALE1)) >> m_coeff.SCALE1);
    int128_t alpha((sum_y - xbeta) / window);

    // Calculate change in slope required for an intercept at t = tau/2.
    int128_t xalpha(alpha * int128_t(m_coeff.kw) + big_dither(m_coeff.SCALE1));
    int128_t delta((xalpha >> m_coeff.SCALE1) + beta);

    // Gradually steer towards the designated target slope.
    m_accum += delta * int128_t(m_coeff.ki);

    // Clamp slew rate to +/- ymax.
    m_accum.clamp(int128_t(m_coeff.ymax) << m_coeff.SCALE);
    return wide_output(m_accum, m_coeff.SCALE);
}
