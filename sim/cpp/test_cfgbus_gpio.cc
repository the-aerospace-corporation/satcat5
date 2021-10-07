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

        // Put the register in "echo" mode and seed PRNG.
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

    SECTION("WrappedRegister") {
        regs[42].read_default_echo();
        satcat5::cfg::WrappedRegister uut(&regs, 42);
        uut = 123;
        CHECK((u32)uut == 123);
    }
}
