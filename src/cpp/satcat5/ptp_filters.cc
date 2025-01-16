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
using satcat5::ptp::LinearPrediction;
using satcat5::ptp::LinearRegression;
using satcat5::ptp::RateConversion;
using satcat5::ptp::SUBNS_PER_NSEC;
using satcat5::ptp::SUBNS_PER_MSEC;
using satcat5::ptp::SUBNS_PER_SEC;
using satcat5::ptp::USEC_PER_SEC;
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

// Set the default slew rate limit for PI and PII controllers.
// (i.e., "10 * SUBNS_PER_MSEC" means max slew of 10 msec/sec.)
constexpr s64 SLEW_MAX_IN  = s64(10 * SUBNS_PER_MSEC);
constexpr u64 SLEW_MAX_OUT = u64(10 * SUBNS_PER_MSEC);

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
    , m_slew(SLEW_MAX_OUT)
{
    set_coeff(coeff);   // For error-reporting.
}

void ControllerPI::set_coeff(const CoeffPI& coeff) {
    m_coeff = coeff;
    if (DEBUG_VERBOSE > 0) {
        auto level = coeff.ok() ? log::DEBUG : log::ERROR;
        log::Log(level, "ControllerPI: Config")
            .write10(m_coeff.kp)
            .write10(m_coeff.ki);
    } else if (!coeff.ok()) {
        log::Log(log::ERROR, "ControllerPI: Bad config.");
    }
}

void ControllerPI::reset() {
    m_accum = INT128_ZERO;
}

void ControllerPI::rate(s64 delta_subns, u32 elapsed_usec) {
    // Limit input to a sensible range...
    delta_subns = satcat5::util::clamp(delta_subns, SLEW_MAX_IN);
    int128_t rate(delta_subns);                 // Range +/- 2^40
    rate <<= m_coeff.SCALE;                     // Range +/- 2^100
    rate *= int128_t(USEC_PER_SEC);             // Range +/- 2^120
    rate /= int128_t(elapsed_usec);             // Range +/- 2^100
    rate.clamp(int128_t(m_slew) << m_coeff.SCALE);
    m_accum += rate;
}

s64 ControllerPI::update(s64 delta_subns, u32 elapsed_usec) {
    // Ignore invalid inputs and clamp to a sensible limit.
    if (delta_subns == INT64_MAX) return INT64_MAX;
    delta_subns = satcat5::util::clamp(delta_subns, SLEW_MAX_IN);

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

    // Clamp accumulator term to mitigate windup.
    int128_t ymax(m_slew);                      // Range 2^33..2^54
    m_accum.clamp(ymax << m_coeff.SCALE);       // Range +/- 2^114

    // Tracking output is the sum of all filter terms.
    // (Sum up to +/- 2^121, output up to +/- 2^61.)
    int128_t ysum(m_accum + delta_p);
    ysum.clamp(ymax << m_coeff.SCALE);
    return wide_output(ysum, m_coeff.SCALE);
}

ControllerPII::ControllerPII(const CoeffPII& coeff)
    : m_coeff(coeff)
    , m_accum1(INT128_ZERO)
    , m_accum2(INT256_ZERO)
    , m_slew(SLEW_MAX_OUT)
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
            .write10(m_coeff.kr);
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
    delta_subns = satcat5::util::clamp(delta_subns, SLEW_MAX_IN);
    int256_t rate(delta_subns);                 // Range +/- 2^40
    rate <<= m_coeff.SCALE;                     // Range +/- 2^174
    rate *= int256_t(USEC_PER_SEC);             // Range +/- 2^194
    rate /= int256_t(elapsed_usec);             // Range +/- 2^174
    rate.clamp(int256_t(SLEW_MAX_OUT) << m_coeff.SCALE);
    m_accum2 += rate;                           // Range +/- 2^188
}

s64 ControllerPII::update(s64 delta_subns, u32 elapsed_usec) {
    // Ignore invalid inputs and clamp to a sensible limit.
    if (delta_subns == INT64_MAX) return INT64_MAX;
    delta_subns = satcat5::util::clamp(delta_subns, SLEW_MAX_IN);

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
    // As with ControllerPI, precalculate gain to ensure continuity
    // and limit the maximum slew-rate to reduce windup.
    int128_t ymax128(m_slew);                   // Range 2^33..2^54
    m_accum1 += delta_i;                        // Range +/- 2^125
    m_accum1.clamp(ymax128 << m_coeff.SCALE1);    // Range +/- 2^124

    // Update the secondary accumulator, i.e.,  sum(sum(K3 * phi)).
    // To avoid using a third accumulator, re-scale the primary by K3 / K2.
    int256_t ymax256(m_slew);                   // Range 2^33..2^54
    int256_t delta_r(m_accum1);                 // Range +/- 2^124
    delta_r *= int256_t(m_coeff.kr);            // Range +/- 2^188
    delta_r *= int256_t(elapsed_usec);          // Range +/- 2^208
    m_accum2 += delta_r;                        // Range +/- 2^209
    m_accum2.clamp(ymax256 << m_coeff.SCALE);   // Range +/- 2^188

    // Tracking output is the sum of all filter terms.
    int128_t ysum((m_accum2 + big_dither(m_coeff.SCALE2)) >> m_coeff.SCALE2);
    ysum += m_accum1;
    ysum += delta_p;
    ysum.clamp(ymax128 << m_coeff.SCALE1);
    return wide_output(ysum, m_coeff.SCALE1);
}

LinearRegression::LinearRegression(
    const unsigned window, const s64* x, const s64* y)
{
    // Calculate the sum of each input vector.
    int128_t sum_x = INT128_ZERO, sum_y = INT128_ZERO;
    for (unsigned n = 0 ; n < window ; ++n) {
        sum_x += int128_t(x[n]);
        sum_y += int128_t(y[n]);
    }

    // Calculate the covariance terms:
    //  cov_xx = sum(dx * dx) and cov_xy = sum(dx * dy),
    //  where dx[n] = x[n] - mean(x) and dy[n] = y[n] - mean(y).
    // To avoid loss of precision, don't divide by the window size:
    //  cov_xx * N^2 = sum(dx' * dx'), where dx' = N*x - sum(x).
    const int128_t win128((u32)window);
    int256_t cov_xx(INT256_ZERO), cov_xy(INT256_ZERO);
    for (unsigned n = 0 ; n < window ; ++n) {
        int256_t dx(int128_t(x[n]) * win128 - sum_x);
        int256_t dy(int128_t(y[n]) * win128 - sum_y);
        cov_xx += dx * dx;
        cov_xy += dx * dy;
    }

    // Calculate slope and intercept by linear regression.
    // https://en.wikipedia.org/wiki/Simple_linear_regression
    beta = int128_t((cov_xy << TSCALE).div_round(cov_xx));
    int128_t xbeta((beta * sum_x + big_dither(TSCALE)) >> TSCALE);
    alpha = int128_t((sum_y - xbeta).div_round(win128));
}

s64 LinearRegression::extrapolate(s64 t) const
{
    return wide_output((alpha << TSCALE) + (beta * int128_t(t)), TSCALE);
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
            .write10(m_coeff.kw);
    } else if (!coeff.ok()) {
        log::Log(log::ERROR, "ControllerLR: Bad config.");
    }
}

void ControllerLR_Inner::rate(s64 delta_subns, u32 elapsed_usec) {
    // Limit input to a sensible range...
    delta_subns = satcat5::util::clamp(delta_subns, SLEW_MAX_IN);
    int128_t rate(delta_subns);
    rate <<= LinearRegression::TSCALE;
    rate *= int128_t(USEC_PER_SEC);
    rate /= int128_t(elapsed_usec);
    m_accum += rate;
}

s64 ControllerLR_Inner::update_inner(const u32* dt, const s64* y) {
    // Convert incremental timesteps to cumulative time,
    // using t = 0 for the most recent input sample.
    // Note: ControllerLR::set_window(...) ensures m_window >= 2.
    s64 x[m_window];    // NOLINT
    x[m_window-1] = 0;
    for (unsigned n = m_window-1 ; n != 0 ; --n) {
        x[n-1] = x[n] - dt[n];
    }

    // Discard degenerate cases where timestamps are too close together.
    s64 span_usec = -x[0];
    if (span_usec < 2000) return INT64_MIN;

    // Calculate slope and intercept by linear regression.
    LinearRegression fit(m_window, x, y);

    // Calculate change in slope required for an intercept at t = tau/2.
    int128_t delta(fit.alpha * int128_t(m_coeff.kw) + fit.beta);

    // Gradually steer towards the designated target slope.
    m_accum += delta * int128_t(m_coeff.ki);

    // Clamp maximum slew rate.
    m_accum.clamp(int128_t(SLEW_MAX_OUT) << fit.TSCALE);
    return wide_output(m_accum, fit.TSCALE);
}

void LinearPrediction::reset() {
    // Reset all inner filter(s).
    satcat5::ptp::Filter* ptr = m_filters.head();
    while (ptr) {
        ptr->reset();
        ptr = m_filters.next(ptr);
    }
    // Reset internal state.
    m_first = 0;
    m_rate = 0;
    m_accum = INT128_ZERO;
}

void LinearPrediction::rate(s64 delta_subns, u32 elapsed_usec) {
    // Update all inner filter(s).
    satcat5::ptp::Filter* ptr = m_filters.head();
    while (ptr) {
        ptr->rate(delta_subns, elapsed_usec);
        ptr = m_filters.next(ptr);
    }
    // Update internal state.
    int128_t rate(delta_subns);                 // Range +/- 2^63
    rate *= int128_t(USEC_PER_SEC);             // Range +/- 2^83
    rate /= int128_t(elapsed_usec);             // Range +/- 2^63
    m_rate = s64(rate);
}

s64 LinearPrediction::update(s64 next, u32 elapsed_usec) {
    if (m_first) {
        // First-time initialization?
        m_accum = int128_t(next) << SCALE;
        m_first = false;
        return next;
    } else {
        // Increment along estimated trendline.
        m_accum += incr(elapsed_usec);
        s64 trend = wide_output(m_accum, SCALE);
        // Compare actual vs predicted and apply each filter.
        s64 delta = next - trend;
        satcat5::ptp::Filter* ptr = m_filters.head();
        while (ptr) {
            delta = ptr->update(delta, elapsed_usec);
            ptr = m_filters.next(ptr);
        }
        // Update accumulator state.
        if (delta != INT64_MIN) m_rate = delta;
        return trend;
    }
}

s64 LinearPrediction::predict(u32 elapsed_usec) const {
    return wide_output(m_accum + incr(elapsed_usec), SCALE);
}

int128_t LinearPrediction::incr(u32 elapsed_usec) const {
    static constexpr u64 TICKS_PER_USEC = satcat5::util::round_u64(
        satcat5::util::pow2d(SCALE) / double(satcat5::ptp::USEC_PER_SEC));
    return int128_t(m_rate) * int128_t(TICKS_PER_USEC) * int128_t(elapsed_usec);
}

s64 RateConversion::convert(s64 offset) const
{
    return wide_output(int128_t(offset) * int128_t(m_scale), SHIFT);
}

s64 RateConversion::invert(s64 rate) const
{
    int128_t temp(rate); temp <<= SHIFT;
    return s64(temp.div_round(int128_t(m_scale)));
}
