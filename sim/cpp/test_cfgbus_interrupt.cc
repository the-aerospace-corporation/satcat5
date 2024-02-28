//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for ConfigBus shared-interrupt handler

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_interrupt.h>

using satcat5::test::MockInterrupt;

TEST_CASE("cfgbus_interrupt") {
    satcat5::log::ToConsole log;    // Logging handler
    satcat5::test::CfgDevice cfg;   // ConfigBus interface
    cfg[1].read_default_echo();
    cfg[2].read_default_echo();
    cfg[3].read_default_echo();

    MockInterrupt uut0(&cfg);       // Test device (no control reg)
    MockInterrupt uut1(&cfg, 1);    // Test device (with control reg)
    MockInterrupt uut2(&cfg, 2);    // Test device (with control reg)
    MockInterrupt uut3(&cfg, 3);    // Test device (with control reg)

    SECTION("count_irq") {
        CHECK(cfg.count_irq() == 4);
    }

    SECTION("reg0") {
        uut0.fire();
        CHECK(uut0.count() == 1);
        CHECK(uut1.count() == 0);
        CHECK(uut2.count() == 0);
        CHECK(uut3.count() == 0);
    }

    SECTION("reg1") {
        uut1.fire();
        uut2.fire();
        uut3.fire();
        CHECK(uut0.count() == 3);   // Unfiltered
        CHECK(uut1.count() == 1);
        CHECK(uut2.count() == 1);
        CHECK(uut3.count() == 1);
    }

    SECTION("disable-enable") {
        uut1.irq_disable();
        uut1.fire();
        uut1.fire();
        CHECK(uut1.count() == 0);
        uut1.irq_enable();
        uut1.fire();
        uut1.fire();
        CHECK(uut1.count() == 2);
    }

    SECTION("double-register") {
        log.suppress("ConfigBus IRQ duplicate");
        cfg.register_irq(&uut1);    // Duplicate registration!?
        CHECK(log.contains("ConfigBus IRQ duplicate"));
        CHECK(cfg.count_irq() == 4);
    }

    SECTION("early-unregister") {
        cfg.unregister_irq(&uut2);      // Pick the one in the middle.
    }
}
