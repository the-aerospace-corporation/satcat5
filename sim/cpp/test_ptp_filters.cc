//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the PTP time-tracking filter

#include <algorithm>
#include <fstream>
#include <hal_test/catch.hpp>
#include <hal_test/ptp_simclock.h>
#include <hal_test/sim_utils.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/utils.h>
#include <satcat5/wide_integer.h>

using satcat5::ptp::CoeffLR;
using satcat5::ptp::CoeffPI;
using satcat5::ptp::CoeffPII;
using satcat5::ptp::SimulatedClock;
using satcat5::util::sign;

static const u32 DEFAULT_INTERVAL_USEC = 125000;

// Signed random numbers with a triangular distribution.
static inline s64 rand_s64() {
    using satcat5::test::rand_u32;
    return s64(rand_u32()) - s64(rand_u32());
}

TEST_CASE("AmplitudeReject") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Unit under test.
    satcat5::ptp::AmplitudeReject uut(2000);

    // Cycle through different standard deviations.
    unsigned scale = GENERATE(0, 2, 4, 8, 16);

    // Generate a randomized input sequence.
    std::vector<s64> input;
    for (unsigned a = 0 ; a < 2048 ; ++a) {
        input.push_back(rand_s64() >> scale);
    }

    SECTION("normal") {
        // Normal test case with a steady input.
        unsigned errors = 0;
        for (unsigned a = 0 ; a < input.size() ; ++a) {
            s64 next = uut.update(input[a], DEFAULT_INTERVAL_USEC);
            if (next != input[a]) ++errors;
        }
        CHECK(errors == 0);
    }

    SECTION("outliers") {
        // This test case adds some outliers in the second half.
        input[1777] = INT32_MAX * 100LL;
        input[1888] = INT32_MAX * 200LL;
        input[1999] = INT32_MAX * 300LL;
        unsigned errors = 0;
        for (unsigned a = 0 ; a < input.size() ; ++a) {
            s64 next = uut.update(input[a], DEFAULT_INTERVAL_USEC);
            if (next != input[a]) ++errors;
        }
        CHECK(errors == 3);
    }

    SECTION("reset") {
        uut.update(123456, DEFAULT_INTERVAL_USEC);
        CHECK(uut.get_mean() != 0);
        uut.reset();
        CHECK(uut.get_mean() == 0);
    }
}
static s64 boxcar(
    const std::vector<s64>& input,
    unsigned index, unsigned window)
{
    // Is there enough history to calculate the full window?
    if (index+1 < window || input.size() <= index) return INT64_MAX;
    // Sum over the designated range.
    s64 temp = 0;
    for (unsigned n = 0 ; n < window ; ++n)
        temp += input[index+n+1-window];
    return temp / window;
}

TEST_CASE("BoxcarFilter") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Unit under test.
    satcat5::ptp::BoxcarFilter<4> uut;

    // Generate a randomized input sequence.
    std::vector<s64> input;
    for (unsigned a = 0 ; a < 1024 ; ++a)
        input.push_back(rand_s64());

    SECTION("filter") {
        unsigned order = GENERATE(0, 1, 2, 3, 4);
        uut.reset();
        uut.set_order(order);
        unsigned errors = 0;
        for (unsigned a = 0 ; a < input.size() ; ++a) {
            s64 ref  = boxcar(input, a, 1u << order);
            s64 next = uut.update(input[a], DEFAULT_INTERVAL_USEC);
            s64 diff = abs(next - ref);
            if (ref != INT64_MAX && diff > 1) ++errors;
        }
        CHECK(errors == 0);
    }
}

TEST_CASE("CoeffLR") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    SECTION("bad_coeff") {
        // Large time constants will eventually overflow.
        SimulatedClock clk(125e6, 125e6);
        CoeffLR coeff1(1.0);
        CoeffLR coeff2(3600.0);
        CoeffLR coeff3(1e15);
        CHECK(coeff1.ok());
        CHECK(coeff2.ok());
        CHECK_FALSE(coeff3.ok());
        // Confirm that loading a bad coefficient logs an error.
        log.suppress("Bad config");
        satcat5::ptp::ControllerLR<16> uut(coeff3);
        CHECK(log.contains("Bad config"));
    }

    SECTION("linear_regression") {
        // Define input points on the line "y = 5 - 10x".
        const s64 x[]  = {-10, -6, -3, -1, 0};
        const s64 y[]  = {105, 65, 35, 15, 5};
        satcat5::ptp::LinearRegression uut(5, x, y);
        // Confirm slope and intercept match expectations.
        CHECK(s64(uut.alpha) == 5);
        CHECK(s64(uut.beta >> uut.TSCALE) == -10LL);
        // Extrapolate to a few test points.
        CHECK(uut.extrapolate(-3) == 35);
        CHECK(uut.extrapolate(-2) == 25);
        CHECK(uut.extrapolate(-1) == 15);
        CHECK(uut.extrapolate(0) == 5);
        CHECK(uut.extrapolate(1) == -5);
        CHECK(uut.extrapolate(2) == -15);
        CHECK(uut.extrapolate(3) == -25);
    }
}

TEST_CASE("CoeffPI") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    SECTION("bad_coeff") {
        // Large time constants will eventually overflow.
        SimulatedClock clk(125e6, 125e6);
        CoeffPI coeff1(1.0);
        CoeffPI coeff2(3600.0);
        CoeffPI coeff3(1e9);
        CHECK(coeff1.ok());
        CHECK(coeff2.ok());
        CHECK_FALSE(coeff3.ok());
        // Confirm that loading a bad coefficient logs an error.
        log.suppress("Bad config");
        satcat5::ptp::ControllerPI uut(coeff3);
        CHECK(log.contains("Bad config"));
    }
}

TEST_CASE("CoeffPII") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    SECTION("bad_coeff") {
        // Large time constants will eventually overflow.
        SimulatedClock clk(125e6, 125e6);
        CoeffPII coeff1(1.0);
        CoeffPII coeff2(3600.0);
        CoeffPII coeff3(1e9);
        CHECK(coeff1.ok());
        CHECK(coeff2.ok());
        CHECK_FALSE(coeff3.ok());
        // Confirm that loading a bad coefficient logs an error.
        log.suppress("Bad config");
        satcat5::ptp::ControllerPII uut(coeff3);
        CHECK(log.contains("Bad config"));
    }
}

static s64 median(
    const std::vector<s64>& input,
    unsigned index, unsigned order)
{
    // Is there enough history to calculate the full window?
    if (index+1 < order || input.size() <= index) return INT64_MAX;
    // Copy data to a working buffer and sort in-place.
    s64 temp[order];
    for (unsigned n = 0 ; n < order ; ++n)
        temp[n] = input[index+n+1-order];
    std::sort(temp, temp + order);
    // Median is the middle element of the sorted vector.
    return temp[(order-1)/2];
}

TEST_CASE("MedianFilter") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Unit under test.
    satcat5::ptp::MedianFilter<15> uut;

    // Generate a randomized input sequence.
    std::vector<s64> input;
    for (unsigned a = 0 ; a < 1024 ; ++a)
        input.push_back(rand_s64());

    SECTION("passthrough") {
        uut.set_order(1);
        unsigned errors = 0;
        for (unsigned a = 0 ; a < input.size() ; ++a) {
            s64 next = uut.update(input[a], DEFAULT_INTERVAL_USEC);
            if (next != input[a]) ++errors;
        }
        CHECK(errors == 0);
    }

    SECTION("standard") {
        unsigned order = GENERATE(3, 5, 7, 9, 11, 13, 15);
        uut.reset();
        uut.set_order(order);
        unsigned errors = 0;
        for (unsigned a = 0 ; a < input.size() ; ++a) {
            s64 ref  = median(input, a, order);
            s64 next = uut.update(input[a], DEFAULT_INTERVAL_USEC);
            if (ref != INT64_MAX && next != ref) ++errors;
        }
        CHECK(errors == 0);
    }
}

TEST_CASE("LinearPrediction") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Unit under test and its counterpart.
    CoeffPI coeff1(1.0);    // Time constant = 1.0 seconds
    satcat5::ptp::ControllerPI ctrl(coeff1);
    satcat5::ptp::LinearPrediction uut(&ctrl);

    // Run some sample data through the filter.
    // Note: TEST_SLOPE is in LSBs per microsecond.
    static const unsigned TEST_SAMPS = 1000;
    static const s64 TEST_TIME   = TEST_SAMPS * DEFAULT_INTERVAL_USEC;
    static const s64 TEST_SLOPE  = 42;
    static const s64 TEST_OFFSET = 123456;
    uut.reset();
    for (unsigned n = 1 ; n <= TEST_SAMPS ; ++n) {
        s64 t = n * DEFAULT_INTERVAL_USEC;
        s64 y = TEST_OFFSET + TEST_SLOPE * t;
        uut.update(y, DEFAULT_INTERVAL_USEC);
    }

    SECTION("predict") {
        // Predict along the current trendline.
        for (unsigned n = 1 ; n <= 20 ; ++n) {
            u32 dt = n * DEFAULT_INTERVAL_USEC;
            s64 y1 = TEST_OFFSET + TEST_SLOPE * (TEST_TIME + dt);
            s64 y2 = uut.predict(dt);
            CHECK(abs(y2 - y1) < 20);
        }
    }

    SECTION("rate") {
        // Make a sudden rate change.
        static const s64 NEW_SLOPE  = -2 * TEST_SLOPE;
        static const s64 NEW_OFFSET = TEST_OFFSET + TEST_SLOPE * TEST_TIME;
        uut.rate(NEW_SLOPE, 1);
        // Run more sample data through the filter.
        for (unsigned n = 1 ; n <= TEST_SAMPS ; ++n) {
            s64 t = n * DEFAULT_INTERVAL_USEC;
            s64 y = NEW_OFFSET + NEW_SLOPE * t;
            uut.update(y, DEFAULT_INTERVAL_USEC);
        }
        // Predict along the new trendline.
        for (unsigned n = 1 ; n <= 20 ; ++n) {
            u32 dt = n * DEFAULT_INTERVAL_USEC;
            s64 y1 = NEW_OFFSET + NEW_SLOPE * (TEST_TIME + dt);
            s64 y2 = uut.predict(dt);
            CHECK(abs(y2 - y1) < 20);
        }
    }
}

TEST_CASE("RateConversion") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Repeat test at various reference frequencies.
    double ref_hz = GENERATE(1e6, -10e6, 100e6, 1e9);

    // Create the unit under test.
    // Match PtpReference scale = 2^40 LSB per nsec.
    satcat5::ptp::RateConversion uut(ref_hz, 40);
    REQUIRE(uut.ok());

    // Test that forward and inverse conversions are self-consistent.
    // (Tolerance of a few LSB is inevitable from repeated rounding.)
    SECTION("fwd_rev") {
        for (unsigned a = 0 ; a < 10 ; ++a) {
            s64 x = rand_s64();
            s64 y = uut.convert(x);
            s64 z = uut.invert(y);
            CHECK(abs(x - z) < 64);
            CHECK(sign(x) == sign(z));
            CHECK(sign(x) == sign(y) * sign(ref_hz));
        }
    }
}
