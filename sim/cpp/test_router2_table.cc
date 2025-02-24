//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the routing table's mirror-to-hardware variant

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/router2_table.h>

// Define register map (see "router2_common.vhd")
static const unsigned CFG_DEVADDR   = 42;
static const unsigned REG_CTRL      = 509;
static const unsigned REG_DATA      = 508;
static const unsigned TABLE_SIZE    = 8;

TEST_CASE("router2_table") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    const satcat5::ip::Addr IP_LOCAL1(192, 168, 1,  12);
    const satcat5::ip::Addr IP_LOCAL2(192, 168, 1,  13);
    const satcat5::eth::MacAddr MAC_LOCAL1 = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE};
    const satcat5::eth::MacAddr MAC_LOCAL2 = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFF};

    // Set up a mock ConfigBus interface.
    satcat5::test::CfgDevice cfg;
    cfg[REG_CTRL].read_default(TABLE_SIZE);
    cfg[REG_DATA].read_default_none();

    // Unit under test.
    satcat5::router2::Table uut(&cfg, CFG_DEVADDR);
    REQUIRE(cfg[REG_CTRL].write_pop() == 0x30000000u);      // Clear on startup.

    SECTION("default") {
        // Load a new default route.
        CHECK(uut.route_default(IP_LOCAL1, MAC_LOCAL1, 0x42));
        // Confirm the expected write sequence.
        CHECK(cfg[REG_DATA].write_pop() == 0x0042DEADu);    // Prefix = 0, Port = 0x42
        CHECK(cfg[REG_DATA].write_pop() == 0xBEEFCAFEu);    // LSBs of MAC address
        CHECK(cfg[REG_DATA].write_pop() == 0);              // IP = Not applicable
        CHECK(cfg[REG_CTRL].write_pop() == 0x20000000u);    // Opcode = Set default
    }

    SECTION("size") {
        CHECK(uut.table_size() == TABLE_SIZE);
    }

    SECTION("write") {
        // Load two table entries.
        CHECK(uut.route_static({IP_LOCAL1, 32}, IP_LOCAL1, MAC_LOCAL1, 0x42));
        CHECK(uut.route_static({IP_LOCAL2, 24}, IP_LOCAL2, MAC_LOCAL2, 0x43));
        // Confirm the first write sequence.
        CHECK(cfg[REG_DATA].write_pop() == 0x2042DEADu);    // Prefix = 32, Port = 0x42
        CHECK(cfg[REG_DATA].write_pop() == 0xBEEFCAFEu);    // LSBs of MAC address
        CHECK(cfg[REG_DATA].write_pop() == 0xC0A8010Cu);    // IP = 192.168.1.12
        CHECK(cfg[REG_CTRL].write_pop() == 0x10000000u);    // Written to row #0
        // Confirm the second write sequence.
        CHECK(cfg[REG_DATA].write_pop() == 0x1843DEADu);    // Prefix = 24, Port = 0x43
        CHECK(cfg[REG_DATA].write_pop() == 0xBEEFCAFFu);    // LSBs of MAC address
        CHECK(cfg[REG_DATA].write_pop() == 0xC0A8010Du);    // IP = 192.168.1.13
        CHECK(cfg[REG_CTRL].write_pop() == 0x10000001u);    // Written to row #1
    }
}
