//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus Timer controller

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_timer.h>
#include <satcat5/polling.h>

// Constants relating to the unit under test:
static const unsigned CFG_DEVADDR   = 42;
static const unsigned REG_WDOG      = 0;
static const unsigned REG_CPU_HZ    = 1;
static const unsigned REG_PERF_CTR  = 2;
static const unsigned REG_LAST_EVT  = 3;
static const unsigned REG_TIMER_LEN = 4;
static const unsigned REG_TIMER_IRQ = 5;
static const uint32_t WDOG_DISABLE  = -1;

TEST_CASE("cfgbus_timer") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Object for counting callback events.
    satcat5::test::CountOnDemand callback;

    // Configure simulated register-map.
    satcat5::test::CfgDevice regs;
    regs[REG_WDOG].read_default_none();
    regs[REG_CPU_HZ].read_default(100e6);       // 100 MHz refclk
    regs[REG_PERF_CTR].read_default_none();
    regs[REG_LAST_EVT].read_default_none();
    regs[REG_TIMER_LEN].read_default_none();
    regs[REG_TIMER_IRQ].read_default(-1);       // Interrupt always ready

    // Unit under test.
    satcat5::cfg::Timer uut(&regs, CFG_DEVADDR);
    uut.timer_callback(&callback);

    // Confirm startup process disables the watchdog timer.
    CHECK(regs[REG_WDOG].write_pop() == WDOG_DISABLE);
    uut.wdog_disable();
    CHECK(regs[REG_WDOG].write_pop() == WDOG_DISABLE);

    SECTION("now") {
        // Read the timer register a few times...
        for (unsigned a = 0 ; a < 10 ; ++a)
            regs[REG_PERF_CTR].read_push(4*a + 7);
        for (unsigned a = 0 ; a < 10 ; ++a)
            CHECK(uut.now() == (4*a + 7));
    }

    SECTION("last_event") {
        // Read the last-event register a few times...
        for (unsigned a = 0 ; a < 10 ; ++a)
            regs[REG_LAST_EVT].read_push(3*a + 2);
        for (unsigned a = 0 ; a < 10 ; ++a)
            CHECK(uut.last_event() == (3*a + 2));
    }

    SECTION("timer_interval") {
        for (unsigned a = 1 ; a < 10 ; ++a) {
            uut.timer_interval(a);  // X usec = X * 100 clocks
            CHECK(regs[REG_TIMER_LEN].write_pop() == 100*a - 1);
        }
    }

    SECTION("timer_callback") {
        // Each interrupt event should trigger a callback.
        for (unsigned a = 0 ; a < 10 ; ++a) {
            CHECK(callback.count() == a);
            regs.irq_poll();            // Trigger a timer interrupt
            satcat5::poll::service();   // Notify test handler
        }
    }

    SECTION("watchdog") {
        // Enable watchdog and confirm write value.
        for (unsigned a = 1 ; a < 10 ; ++a) {
            uut.wdog_update(a);     // X usec = X * 100 clocks
            CHECK(regs[REG_WDOG].write_pop() == 100*a);
        }
    }
}
