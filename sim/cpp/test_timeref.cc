//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for TimeRef and TimeRefRegister functions.

#include <ctime>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/timeref.h>

using satcat5::util::TimeVal;

// Test timestamp overflow from UINT32_MAX to zero.
static constexpr u32 WRAP = u32(-1);

// Timer object that simply returns a constant.
// For test purposes, resolution is fixed at 16 ticks per microsecond.
class ConstantTimer : public satcat5::util::TimeRef {
public:
    explicit ConstantTimer()
        : TimeRef(16000000), m_now(0) {}
    u32 raw() override  {return m_now;}
    void set(u32 t)     {m_now = t;}
protected:
    u32 m_now;
};

TEST_CASE("TimeRef") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Create timestamps with different initial values.
    ConstantTimer clk;
    TimeVal t00     {&clk, 0};
    TimeVal t05     {&clk, 5};
    TimeVal t64     {&clk, 64};
    TimeVal twr     {&clk, WRAP};

    SECTION("elapsed_tick") {
        clk.set(0);     CHECK(t00.elapsed_tick() == 0);
        clk.set(0);     CHECK(twr.elapsed_tick() == 1);
        clk.set(63);    CHECK(t64.elapsed_tick() == WRAP);
        clk.set(63);    CHECK(twr.elapsed_tick() == 64);
        clk.set(64);    CHECK(t00.elapsed_tick() == 64);
        clk.set(64);    CHECK(twr.elapsed_tick() == 65);
        clk.set(WRAP);  CHECK(t00.elapsed_tick() == WRAP);
    }

    SECTION("elapsed_usec") {
        clk.set(0);     CHECK(t00.elapsed_usec() == 0);
        clk.set(0);     CHECK(twr.elapsed_usec() == 0);
        clk.set(63);    CHECK(t00.elapsed_usec() == 3);
        clk.set(63);    CHECK(twr.elapsed_usec() == 4);
        clk.set(64);    CHECK(t00.elapsed_usec() == 4);
        clk.set(64);    CHECK(twr.elapsed_usec() == 4);
    }

    SECTION("elapsed_msec") {
        // 64000 = 4 msec exactly
        clk.set(63999); CHECK(twr.elapsed_msec() == 4);
        clk.set(63999); CHECK(t00.elapsed_msec() == 3);
        clk.set(64000); CHECK(t00.elapsed_msec() == 4);
    }

    SECTION("increment_usec") {
        clk.set(64);
        CHECK(t00.increment_usec() == 4);
        CHECK(t00.tval == 64);
        CHECK(t00.increment_usec() == 0);
        CHECK(t00.tval == 64);
    }

    SECTION("increment_msec") {
        clk.set(64);
        CHECK(t00.increment_msec() == 0);
        CHECK(t00.tval == 0);               // No change (increment < 1 msec)
        clk.set(65536);
        CHECK(t00.increment_msec() == 4);
        CHECK(t00.tval == 64000);           // 65536 = 4 msec + 1536 ticks
        clk.set(70000);
        CHECK(t00.increment_msec() == 0);
        CHECK(t00.tval == 64000);           // No change (increment < 1 msec)
    }

    SECTION("interval_usec") {
        clk.set(64);
        CHECK_FALSE(t05.interval_usec(5));
        CHECK(t05.tval == 5);
        CHECK_FALSE(t05.interval_usec(4));
        CHECK(t05.tval == 5);
        CHECK(t05.interval_usec(3));
        CHECK(t05.tval == 53);
    }

    SECTION("interval_msec") {
        clk.set(65536);
        CHECK_FALSE(t05.interval_msec(5));
        CHECK(t05.tval == 5);
        CHECK(t05.interval_msec(4));
        CHECK(t05.tval == 64005);
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

    SECTION("checkpoint_usec") {
        auto tref = clk.checkpoint_usec(3);
        CHECK(tref.tval == 48);
        clk.set(47);
        CHECK_FALSE(tref.checkpoint_elapsed());
        CHECK(tref.tval == 48);
        clk.set(48);
        CHECK(tref.checkpoint_elapsed());
        CHECK(tref.tval == 0);
    }

    SECTION("checkpoint_msec") {
        auto tref = clk.checkpoint_msec(3);
        CHECK(tref.tval == 48000);
        clk.set(47999);
        CHECK_FALSE(tref.checkpoint_elapsed());
        CHECK(tref.tval == 48000);
        clk.set(48001);
        CHECK(tref.checkpoint_elapsed());
        CHECK(tref.tval == 0);
    }
}

TEST_CASE("TimeRegister") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    const u32 CLK_HZ = 100e6;
    u32 reg = 0;
    satcat5::util::TimeRegister uut(&reg, CLK_HZ);
    auto tref = uut.now();

    SECTION("elapsed") {
        reg = CLK_HZ / 100;
        CHECK(tref.elapsed_usec() == 10000);
        reg = CLK_HZ / 50;
        CHECK(tref.elapsed_usec() == 20000);
    }

    SECTION("raw") {
        reg = 1 * CLK_HZ;
        CHECK(uut.raw() == 1 * CLK_HZ);
        reg = 2 * CLK_HZ;
        CHECK(uut.raw() == 2 * CLK_HZ);
    }
}
