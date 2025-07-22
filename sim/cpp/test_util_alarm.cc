//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the duration/threshold alarm system.

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/util_alarm.h>

static_assert(SATCAT5_MAX_ALARMS >= 2);
using satcat5::util::Alarm;

// Define a fixed value-vs-time sequence for each test:
static constexpr u32 TEST1[] =
    // Alarms:                   **          **
    {10, 11, 12, 13, 14, 15, 16, 16, 10, 10, 21, 10};
static constexpr unsigned TEST1_LEN = sizeof(TEST1) / sizeof(u32);

TEST_CASE("util_alarm") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;

    // Unit under test.
    Alarm uut;

    // Simple test with a two-part profile:
    //  * Alarm if input > 20 (instantaneous).
    //  * Alarm if input > 15 for 2 consecutive samples.
    SECTION("test1") {
        uut.limit_clear();
        uut.limit_add(0, 20);
        uut.limit_add(2, 15);
        for (unsigned t = 0 ; t < TEST1_LEN ; ++t) {
            bool alarm = uut.push_next(TEST1[t]);
            CHECK(uut.value() == TEST1[t]);
            if (t == 7 || t == 10) {
                CHECK(alarm);
            } else {
                CHECK_FALSE(alarm);
            }
            if (t < 7) {
                CHECK_FALSE(uut.sticky_alarm());
            } else {
                CHECK(uut.sticky_alarm());
            }
            timer.sim_wait(1);
        }
        uut.sticky_clear();
        CHECK_FALSE(uut.sticky_alarm());
    }
}
