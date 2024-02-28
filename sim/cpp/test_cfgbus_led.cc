//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus LED controllers

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_led.h>
#include <satcat5/cfgbus_stats.h>

// Constants relating to the unit under test:
static const unsigned LED_DEVADDR = 42;
static const unsigned NET_DEVADDR = 43;
static const unsigned TEST_LEDS   = 12;

using satcat5::cfg::LedArray;
using satcat5::cfg::LedActivity;
using satcat5::cfg::LedActivityCtrl;
using satcat5::cfg::LedWave;
using satcat5::cfg::LedWaveCtrl;

TEST_CASE("cfgbus_led") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // PRNG for these tests.
    Catch::SimplePcg32 rng;

    // Instantiate simulated register map.
    satcat5::test::CfgDevice cfg;

    // Trigger timers on every call to poll::service().
    satcat5::test::TimerAlways timer;

    // Put each LED register in "echo" mode.
    for (unsigned a = 0 ; a < TEST_LEDS ; ++a)
        cfg[a].read_default_echo();

    SECTION("array") {
        // Unit under test.
        LedArray led(&cfg, LED_DEVADDR, TEST_LEDS);

        // Set and readback at random, including out-of-bounds access.
        for (unsigned a = 0 ; a < 20 ; ++a) {
            unsigned idx = (unsigned)rng() % (2*TEST_LEDS);
            u8 val = (u8)(rng() % 256);
            led.set(idx, val);
            CHECK(led.get(idx) == (idx < TEST_LEDS ? val : 0));
        }
    }

    SECTION("activity") {
        // Simulated network statistics.
        satcat5::test::MockConfigBusMmap mmap;
        satcat5::cfg::NetworkStats stats(&mmap, NET_DEVADDR);
        satcat5::cfg::Register stats_reg = mmap.get_register(NET_DEVADDR);

        // Unit under test.
        LedActivityCtrl uut(&stats, 1);     // Accelerated animation
        LedActivity uut0(&cfg, LED_DEVADDR, 0, 0); uut.add(&uut0);
        LedActivity uut1(&cfg, LED_DEVADDR, 1, 1); uut.add(&uut1);
        LedActivity uut2(&cfg, LED_DEVADDR, 2, 2); uut.add(&uut2);
        LedActivity uut3(&cfg, LED_DEVADDR, 3, 3); uut.add(&uut3);

        // Run many simulated animation frames.
        for (unsigned a = 0 ; a < 1000 ; ++a) {
            // Clear all port traffic counters.
            mmap.clear_dev(NET_DEVADDR);
            // Occasionally mark activity on a randomly selected port.
            // (The "rcvd_frames" register is index 2 of 8 within each port.)
            unsigned sel = (unsigned)rng() % 2;
            unsigned prt = (unsigned)rng() % 4;
            if (sel == 0) stats_reg[8*prt + 3] = 1;
            // Run animation
            satcat5::poll::service();
        }
    }

    SECTION("wave") {
        // Unit under test.
        LedWaveCtrl uut;
        LedWave uut0(&cfg, LED_DEVADDR, 0); uut.add(&uut0);
        LedWave uut1(&cfg, LED_DEVADDR, 1); uut.add(&uut1);
        LedWave uut2(&cfg, LED_DEVADDR, 2); uut.add(&uut2);
        LedWave uut3(&cfg, LED_DEVADDR, 3); uut.add(&uut3);
        uut.start(1);                   // Accelerated animation

        // Run many simulated animation frames.
        for (unsigned a = 0 ; a < 100 ; ++a)
            satcat5::poll::service();

        uut.stop();
    }

}
