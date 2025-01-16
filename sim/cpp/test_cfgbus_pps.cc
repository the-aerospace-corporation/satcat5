//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the pulse-per-second (PPS) input and output

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_pps.h>
#include <satcat5/ptp_tracking.h>

// Constants relating to the unit under test:
static const unsigned CFG_DEVADDR   = 42;
static const unsigned REG_PPSI      = 1;
static const unsigned REG_PPSO      = 2;


TEST_CASE("cfgbus_ppsi") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;

    // Simulated memory-map and device under test.
    satcat5::test::CfgDevice regs;
    regs[REG_PPSI].read_default(0);
    satcat5::cfg::PpsInput uut(
        regs.get_register(CFG_DEVADDR, REG_PPSI));

    // Set up a TrackingController to receive pulse information.
    satcat5::ptp::TrackingController trk(nullptr);
    satcat5::ptp::DebugFilter dbg;
    trk.add_filter(&dbg);
    trk.reset(true);
    uut.set_callback(&trk);

    // Confirm expected startup configuration.
    CHECK(regs[REG_PPSI].write_pop() == 1);

    // Test the offset accessors.
    SECTION("offset") {
        uut.set_offset(1234);
        CHECK(uut.get_offset() == 1234);
    }

    // Read a simulated pulse descriptor.
    SECTION("read_pulse") {
        // Write a pulse to the simulated FIFO.
        regs[REG_PPSI].read_push(0x40000000u);
        regs[REG_PPSI].read_push(0x40000000u);
        regs[REG_PPSI].read_push(0x40012345u);
        regs[REG_PPSI].read_push(0xC06789ABu);
        // Wait for the unit under test to read it.
        timer.sim_wait(1000);
        // Confirm the first pulse was processed.
        CHECK(dbg.prev() == -0x123456789ABll);
        // Write another pulse with offset = 999,999,999 nsec.
        regs[REG_PPSI].read_push(0x40000000u);
        regs[REG_PPSI].read_push(0x40000001u);
        regs[REG_PPSI].read_push(0x403B9AC9u);
        regs[REG_PPSI].read_push(0xC0FF0000u);
        // Wait for the unit under test to read it.
        timer.sim_wait(1000);
        // Confirm the second pulse was processed.
        CHECK(dbg.prev() == 65536);
    }
}

TEST_CASE("cfgbus_ppso") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Simulated memory-map and device under test.
    satcat5::test::CfgDevice regs;
    regs[REG_PPSO].read_default(0);
    satcat5::cfg::PpsOutput uut(
        regs.get_register(CFG_DEVADDR, REG_PPSO));

    // Confirm expected startup configuration.
    CHECK(regs[REG_PPSO].write_pop() == 0x80000000u);
    CHECK(regs[REG_PPSO].write_pop() == 0x00000000u);

    // Confirm phase-offset configuration.
    SECTION("set_offset") {
        uut.set_offset(0x123456789ABll);
        CHECK(regs[REG_PPSO].write_pop() == 0x80000123u);
        CHECK(regs[REG_PPSO].write_pop() == 0x456789ABu);
        uut.set_offset(-1);
        CHECK(regs[REG_PPSO].write_pop() == 0x8000FFFFu);
        CHECK(regs[REG_PPSO].write_pop() == 0xFFFFFFFFu);
    }

    // Confirm rising/falling-edge configuration.
    SECTION("set_polarity") {
        uut.set_polarity(false);
        CHECK(regs[REG_PPSO].write_pop() == 0x00000000u);
        CHECK(regs[REG_PPSO].write_pop() == 0x00000000u);
        uut.set_polarity(true);
        CHECK(regs[REG_PPSO].write_pop() == 0x80000000u);
        CHECK(regs[REG_PPSO].write_pop() == 0x00000000u);
    }
}
