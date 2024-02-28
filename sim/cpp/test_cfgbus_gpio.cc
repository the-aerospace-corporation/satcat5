//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus GPIO controllers

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_gpio.h>

// Constants relating to the unit under test:
static const unsigned CFG_DEVADDR = 42;
static const unsigned CFG_REG_GPI = 43;
static const unsigned CFG_REG_GPO = 44;

TEST_CASE("cfgbus_gpio") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // PRNG for these tests.
    Catch::SimplePcg32 rng;

    // Instantiate simulated register map.
    satcat5::test::CfgDevice regs;

    SECTION("gpi") {
        satcat5::cfg::GpiRegister gpi(&regs, CFG_DEVADDR, CFG_REG_GPI);

        // We expect two reads during this test.
        regs[CFG_REG_GPI].read_default_none();
        regs[CFG_REG_GPI].read_push(0x1234);
        regs[CFG_REG_GPI].read_push(0x5678);

        // Basic read
        CHECK(gpi.read() == 0x1234);

        // Synchronized read
        CHECK(gpi.read_sync() == 0x5678);
        CHECK(regs[CFG_REG_GPI].write_count() == 1);
    }

    SECTION("gpo") {
        satcat5::cfg::GpoRegister gpo(&regs, CFG_DEVADDR, CFG_REG_GPO);

        // Put the register in "echo" mode.
        regs[CFG_REG_GPO].read_default_echo();

        // Test each possible operation a few times.
        // (Read-back after each operation to check expected value.)
        for (unsigned a = 0 ; a < 10 ; ++a) {
            u32 x = rng(), y = rng();
            gpo.write(x);       // Set initial value
            CHECK(gpo.read() == x);
            gpo.mask_clr(y);    // Clear bit-mask
            CHECK(gpo.read() == (x & ~y));
            gpo.mask_set(y);    // Set bit-mask
            CHECK(gpo.read() == (x | y));
        }
    }

    SECTION("gpio") {
        satcat5::cfg::GpioRegister gpio(&regs, CFG_DEVADDR);

        // Set the mode for each control register.
        regs[0].read_default_echo();    // Mode
        regs[1].read_default_echo();    // Output
        regs[2].read_default_none();    // Input
        regs[2].read_push(0x1234);
        regs[2].read_push(0x5678);

        // Test the read() function.
        CHECK(gpio.read() == 0x1234);
        CHECK(gpio.read() == 0x5678);

        // Test each mode and output operation a few times.
        // (Read-back after each operation to check expected value.)
        for (unsigned a = 0 ; a < 10 ; ++a) {
            u32 x = rng(), y = rng(), z = rng();
            gpio.mode(x);       // Set initial mode
            gpio.write(y);      // Set initial output
            CHECK(regs[0].write_pop() == x);
            CHECK(regs[1].write_pop() == y);
            gpio.mode_clr(z);
            gpio.out_clr(z);
            CHECK(regs[0].write_pop() == (x & ~z));
            CHECK(regs[1].write_pop() == (y & ~z));
            gpio.mode_set(z);
            gpio.out_set(z);
            CHECK(regs[0].write_pop() == (x | z));
            CHECK(regs[1].write_pop() == (y | z));
        }
    }
}
