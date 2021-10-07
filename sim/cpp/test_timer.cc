//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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
// Test cases for GenericTimer and TimerRegister functions.

#include <ctime>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/timer.h>

TEST_CASE("GenericTimer") {
    satcat5::test::ConstantTimer t00(0);
    satcat5::test::ConstantTimer t64(64);

    SECTION("elapsed_ticks") {
        CHECK(t00.elapsed_ticks(0) == 0);
        CHECK(t00.elapsed_ticks(-1) == 1);  // Wraparound

        CHECK(t64.elapsed_ticks(0) == 64);
        CHECK(t64.elapsed_ticks(1) == 63);
        CHECK(t64.elapsed_ticks(63) == 1);
        CHECK(t64.elapsed_ticks(-1) == 65); // Wraparound
    }

    SECTION("elapsed_usec") {
        CHECK(t00.elapsed_usec(0) == 0);
        CHECK(t00.elapsed_usec(-1) == 0);   // Wraparound

        CHECK(t64.elapsed_usec(0) == 4);
        CHECK(t64.elapsed_usec(1) == 3);
        CHECK(t64.elapsed_usec(63) == 0);
        CHECK(t64.elapsed_usec(-1) == 4);   // Wraparound
    }

    SECTION("elapsed_incr") {
        u32 tref = 0;
        CHECK(t64.elapsed_incr(tref) == 4);
        CHECK(tref == 64);
        CHECK(t64.elapsed_incr(tref) == 0);
    }

    SECTION("elapsed_test") {
        u32 tref = 5;
        CHECK(!t64.elapsed_test(tref, 5));
        CHECK(tref == 5);
        CHECK(!t64.elapsed_test(tref, 4));
        CHECK(tref == 5);
        CHECK(t64.elapsed_test(tref, 3));
        CHECK(tref == 64);
    }

    SECTION("busywait_test") {
        satcat5::util::PosixTimer timer;
        // Request a busywait delay of 100 msec.
        clock_t start = clock();
        timer.busywait_usec(100000);
        clock_t elapsed = clock() - start;
        // Confirm measured time is reasonably accurate.
        CHECK(elapsed <= CLOCKS_PER_SEC/8);
        CHECK(elapsed >= CLOCKS_PER_SEC/12);
    }

    SECTION("checkpoint") {
        u32 tref = t00.get_checkpoint(3);
        CHECK(tref == 48);
        CHECK(!t00.checkpoint_elapsed(tref));
        CHECK(tref == 48);
        CHECK(t64.checkpoint_elapsed(tref));
        CHECK(tref == 0);
    }
}

TEST_CASE("TimerRegister") {
    const u32 CLK_HZ = 100e6;
    u32 reg = 0;
    satcat5::util::TimerRegister uut(&reg, CLK_HZ);

    SECTION("elapsed") {
        reg = CLK_HZ / 100;
        CHECK(uut.elapsed_usec(0) == 10000);
        reg = CLK_HZ / 50;
        CHECK(uut.elapsed_usec(0) == 20000);
    }

    SECTION("now") {
        reg = 1 * CLK_HZ;
        CHECK(uut.now() == 1 * CLK_HZ);
        reg = 2 * CLK_HZ;
        CHECK(uut.now() == 2 * CLK_HZ);
    }
}
