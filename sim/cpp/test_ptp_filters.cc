//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the PTP time-tracking filter

#include <algorithm>
#include <fstream>
#include <hal_test/catch.hpp>
#include <hal_test/ptp_clock.h>
#include <hal_test/sim_utils.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/utils.h>
#include <satcat5/wide_integer.h>

using satcat5::ptp::CoeffLR;
using satcat5::ptp::CoeffPI;
using satcat5::ptp::CoeffPII;
using satcat5::ptp::SimulatedClock;

static const u32 DEFAULT_INTERVAL_USEC = 125000;

TEST_CASE("AmplitudeReject") {
    // Unit under test.
    satcat5::ptp::AmplitudeReject uut(2000);

    // Cycle through different standard deviations.
    unsigned scale = GENERATE(0, 2, 4, 8, 16);

    // Generate a randomized input sequence.
    auto rng = Catch::rng();
    std::vector<s64> input;
    for (unsigned a = 0 ; a < 2048 ; ++a) {
        s64 delta = s64(rng()) - s64(rng());
        input.push_back(delta >> scale);
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
    // Unit under test.
    satcat5::ptp::BoxcarFilter<4> uut;

    // Generate a randomized input sequence.
    auto rng = Catch::rng();
    std::vector<s64> input;
    for (unsigned a = 0 ; a < 1024 ; ++a)
        input.push_back(s64(rng()) - s64(rng()));

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
    satcat5::log::ToConsole log;

    SECTION("bad_coeff") {
        // Large time constants will eventually overflow.
        SimulatedClock clk(125e6, 125e6);
        CoeffLR coeff1(clk.ref_scale(), 1.0);
        CoeffLR coeff2(clk.ref_scale(), 3600.0);
        CoeffLR coeff3(clk.ref_scale(), 1e15);
        CHECK(coeff1.ok());
        CHECK(coeff2.ok());
        CHECK_FALSE(coeff3.ok());
        // Confirm that loading a bad coefficient logs an error.
        log.suppress("Bad config");
        satcat5::ptp::ControllerLR<16> uut(coeff3);
        CHECK(log.contains("Bad config"));
    }

    SECTION("dynamic_range") {
        // Confirm rated limits on minimum and maximum parameters.
        CHECK(CoeffLR(1e-10,    1.0).ok());
        CHECK(CoeffLR(1e-10, 3600.0).ok());
        CHECK(CoeffLR(1e-16,    1.0).ok());
        CHECK(CoeffLR(1e-16, 3600.0).ok());
    }
}

TEST_CASE("CoeffPI") {
    // Simulation infrastructure.
    satcat5::log::ToConsole log;

    SECTION("bad_coeff") {
        // Large time constants will eventually overflow.
        SimulatedClock clk(125e6, 125e6);
        CoeffPI coeff1(clk.ref_scale(), 1.0);
        CoeffPI coeff2(clk.ref_scale(), 3600.0);
        CoeffPI coeff3(clk.ref_scale(), 1e9);
        CHECK(coeff1.ok());
        CHECK(coeff2.ok());
        CHECK_FALSE(coeff3.ok());
        // Confirm that loading a bad coefficient logs an error.
        log.suppress("Bad config");
        satcat5::ptp::ControllerPI uut(coeff3);
        CHECK(log.contains("Bad config"));
    }

    SECTION("dynamic_range") {
        // Confirm rated limits on minimum and maximum parameters.
        CHECK(CoeffPI(1e-10,    1.0).ok());
        CHECK(CoeffPI(1e-10, 3600.0).ok());
        CHECK(CoeffPI(1e-16,    1.0).ok());
        CHECK(CoeffPI(1e-16, 3600.0).ok());
    }
}

TEST_CASE("CoeffPII") {
    // Simulation infrastructure.
    satcat5::log::ToConsole log;

    SECTION("bad_coeff") {
        // Large time constants will eventually overflow.
        SimulatedClock clk(125e6, 125e6);
        CoeffPII coeff1(clk.ref_scale(),1.0);
        CoeffPII coeff2(clk.ref_scale(), 3600.0);
        CoeffPII coeff3(clk.ref_scale(), 1e9);
        CHECK(coeff1.ok());
        CHECK(coeff2.ok());
        CHECK_FALSE(coeff3.ok());
        // Confirm that loading a bad coefficient logs an error.
        log.suppress("Bad config");
        satcat5::ptp::ControllerPII uut(coeff3);
        CHECK(log.contains("Bad config"));
    }

    SECTION("dynamic_range") {
        // Confirm rated limits on minimum and maximum parameters.
        CHECK(CoeffPII(1e-10,    1.0).ok());
        CHECK(CoeffPII(1e-10, 3600.0).ok());
        CHECK(CoeffPII(1e-16,    1.0).ok());
        CHECK(CoeffPII(1e-16, 3600.0).ok());
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
    // Unit under test.
    satcat5::ptp::MedianFilter<15> uut;

    // Generate a randomized input sequence.
    auto rng = Catch::rng();
    std::vector<s64> input;
    for (unsigned a = 0 ; a < 1024 ; ++a)
        input.push_back(s64(rng()) - s64(rng()));

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
