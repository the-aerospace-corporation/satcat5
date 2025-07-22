//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the piezo buzzer driver

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_piezo.h>

// Constants relating to the unit under test:
static const unsigned DEVADDR = 42;
static const unsigned REGADDR = 5;

TEST_CASE("cfgbus_piezo") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;

    // Simulated memory-map and device under test.
    satcat5::test::CfgDevice regs;
    regs[REGADDR].read_default_none();
    satcat5::cfg::Piezo uut(&regs, DEVADDR, REGADDR);

    // Confirm that speaker is silenced on startup.
    CHECK(regs[REGADDR].write_pop() == 0);

    // Basic test with a sequence of notes.
    SECTION("basic") {
        // Write four notes to the command queue.
        // (Duration / frequency / duration / frequency...)
        auto wr = uut.queue();
        wr->write_u16(100);
        wr->write_u32(1234);
        wr->write_u16(100);
        wr->write_u32(2345);
        wr->write_u16(100);
        wr->write_u32(3456);
        wr->write_u16(100);
        wr->write_u32(4567);
        wr->write_finalize();
        // Confirm the commands are executed on time.
        timer.sim_wait(50);
        CHECK(regs[REGADDR].write_pop() == 1234);
        timer.sim_wait(100);
        CHECK(regs[REGADDR].write_pop() == 2345);
        timer.sim_wait(100);
        CHECK(regs[REGADDR].write_pop() == 3456);
        timer.sim_wait(100);
        CHECK(regs[REGADDR].write_pop() == 4567);
        timer.sim_wait(100);
        CHECK(regs[REGADDR].write_pop() == 0);
    }

    SECTION("flush") {
        // Write two notes to the command queue.
        // (Duration / frequency / duration / frequency...)
        auto wr = uut.queue();
        wr->write_u16(100);
        wr->write_u32(1234);
        wr->write_u16(100);
        wr->write_u32(2345);
        wr->write_finalize();
        // In the middle of the first note, flush the queue.
        timer.sim_wait(50);
        CHECK(regs[REGADDR].write_pop() == 1234);
        uut.flush();
        CHECK(regs[REGADDR].write_pop() == 0);
        // Wait a second, then play another note.
        timer.sim_wait(1000);
        wr->write_u16(100);
        wr->write_u32(3456);
        wr->write_finalize();
        // Confirm the commands are executed on time.
        timer.sim_wait(50);
        CHECK(regs[REGADDR].write_pop() == 3456);
        timer.sim_wait(100);
        CHECK(regs[REGADDR].write_pop() == 0);
    }
}
