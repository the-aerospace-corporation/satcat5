//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus core functions

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_core.h>

static constexpr unsigned BULK_LEN = 100;

TEST_CASE("cfgbus_core") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Instantiate simulated register map.
    satcat5::test::CfgDevice regs;
    regs.read_default_none();

    // Working buffer for reads and writes.
    u32 buffer[BULK_LEN];

    SECTION("read_array") {
        for (u32 a = 0 ; a < BULK_LEN ; ++a)
            regs[42 + a].read_push(a);
        regs.read_array(42, BULK_LEN, buffer);
        for (u32 a = 0 ; a < BULK_LEN ; ++a)
            CHECK(buffer[a] == a);
    }

    SECTION("read_repeat") {
        for (u32 a = 0 ; a < BULK_LEN ; ++a)
            regs[42].read_push(a);
        regs.read_repeat(42, BULK_LEN, buffer);
        for (u32 a = 0 ; a < BULK_LEN ; ++a)
            CHECK(buffer[a] == a);
    }

    SECTION("write_array") {
        for (u32 a = 0 ; a < BULK_LEN ; ++a)
            buffer[a] = a;
        regs.write_array(42, BULK_LEN, buffer);
        for (u32 a = 0 ; a < BULK_LEN ; ++a)
            CHECK(regs[42+a].write_pop() == a);
    }

    SECTION("write_repeat") {
        for (u32 a = 0 ; a < BULK_LEN ; ++a)
            buffer[a] = a;
        regs.write_repeat(42, BULK_LEN, buffer);
        for (u32 a = 0 ; a < BULK_LEN ; ++a)
            CHECK(regs[42].write_pop() == a);
    }

    SECTION("WrappedRegister") {
        regs[42].read_default_echo();
        satcat5::cfg::WrappedRegister uut(&regs, 42);
        uut = 123;
        CHECK((u32)uut == 123);
    }
}
