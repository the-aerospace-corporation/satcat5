//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the Ring Tone Text Transfer Language (RTTTL) interpreter

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/codec_rtttl.h>
#include <satcat5/log.h>

using satcat5::io::Readable;

// Typical 100 MHz reference clock is used for all tests.
static constexpr u64 REFCLK_HZ = 100000000;

// Define function for checking each note.
static void check_note(Readable* spkr, u16 duration, u32 freq) {
    if (freq) {
        REQUIRE(spkr->get_read_ready() >= 12);
        u16 gap = duration / 16;
        CHECK(spkr->read_u16() == (duration - gap));
        CHECK(spkr->read_u32() == freq);
        CHECK(spkr->read_u16() == gap);
        CHECK(spkr->read_u32() == 0);
    } else {
        REQUIRE(spkr->get_read_ready() >= 6);
        CHECK(spkr->read_u16() == duration);
        CHECK(spkr->read_u32() == 0);
    }
}

// Helper function for testing output of a log message.
static unsigned log_test(satcat5::io::Readable* spkr, s8 priority) {
    // Write a message to the log.
    satcat5::log::Log(priority, "Test message").write10(s32(priority));
    // Note how much data was generated, then flush the buffer.
    unsigned num_read = spkr->get_read_ready();
    spkr->read_consume(num_read);
    return num_read;
}

TEST_CASE("codec_rtttl") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;

    // Opening bars from Beethoven's 5th symphony.
    // (100 BPM -> Whole note = 600 msec.)
    SECTION("Beethoven") {
        // Unit under test with decoder + large buffer.
        satcat5::io::StreamBufferHeap spkr(4096);
        satcat5::io::RtttlDecoder uut(&spkr, REFCLK_HZ);
        // Load the song.
        REQUIRE(uut.play(satcat5::io::RTTTL_BEETHOVEN));
        // Confirm expected outputs.
        check_note(&spkr,  37, 33672);  // g
        check_note(&spkr,  37, 33672);  // g
        check_note(&spkr,  37, 33672);  // g
        check_note(&spkr, 150, 26726);  // 4d#
        check_note(&spkr, 150,     0);  // 4p
        check_note(&spkr,  37, 29998);  // f
        check_note(&spkr,  37, 29998);  // f
        check_note(&spkr,  37, 29998);  // f
        check_note(&spkr, 150, 25226);  // 4d
        check_note(&spkr, 150,     0);  // 4p
        check_note(&spkr,  37, 33672);  // g
        check_note(&spkr,  37, 33672);  // g
        check_note(&spkr,  37, 33672);  // g
        check_note(&spkr,  37, 26726);  // d#
        check_note(&spkr,  37, 35674);  // g#
        check_note(&spkr,  37, 35674);  // g#
        check_note(&spkr,  37, 35674);  // g#
        check_note(&spkr,  37, 33672);  // g
        check_note(&spkr,  37, 53451);  // d#6
        check_note(&spkr,  37, 53451);  // d#6
        check_note(&spkr,  37, 53451);  // d#6
        check_note(&spkr, 150, 44947);  // 4c6
        check_note(&spkr,  75,     0);  // 8p
        CHECK(spkr.get_read_ready() == 0);
    }

    // "Haunted House" example from Wikipedia.
    // (108 BPM -> Whole note = 555 msec.)
    SECTION("Haunted") {
        // Unit under test with decoder + small buffer.
        // Use a very small working buffer to force chunky output.
        satcat5::io::StreamBufferHeap spkr(64);
        satcat5::io::RtttlDecoder uut(&spkr, REFCLK_HZ);
        // Load the song.
        REQUIRE(uut.play(satcat5::io::RTTTL_HAUNTED));
        // Confirm expected outputs.
        check_note(&spkr, 277, 18898);  // 2a4
        check_note(&spkr, 277, 28315);  // 2e
        check_note(&spkr, 277, 26726);  // 2d#
        satcat5::poll::service();       // Refill working buffer
        check_note(&spkr, 277, 21212);  // 2b4
        check_note(&spkr, 277, 18898);  // 2a4
        check_note(&spkr, 277, 22473);  // 2c
        satcat5::poll::service();       // Refill working buffer
        check_note(&spkr, 277, 25226);  // 2d
        check_note(&spkr, 277, 20022);  // 2a#4
        check_note(&spkr, 416, 28315);  // 2e.
        satcat5::poll::service();       // Refill working buffer
        CHECK(spkr.get_read_ready() == 0);
    }

    // Test the log::ToBeep adapter class.
    SECTION("ToBeep") {
        // Unit under test with decoder + large buffer.
        satcat5::io::StreamBufferHeap spkr(4096);
        satcat5::io::RtttlDecoder uut(&spkr, REFCLK_HZ);
        // Attach logging system to the RTTTL decoder.
        satcat5::log::ToBeep beep(&uut);
        beep.set_cooldown(50);
        // Suppress display of our test messages...
        log.suppress("Test message");
        // Two messages in rapid succession should only beep once.
        CHECK(spkr.get_read_ready() == 0);
        CHECK(log_test(&spkr, satcat5::log::CRITICAL) > 0);
        CHECK(log_test(&spkr, satcat5::log::CRITICAL) == 0);
        // After a short delay, send test messages at each priority.
        timer.sim_wait(100);
        CHECK(log_test(&spkr, satcat5::log::ERROR) > 0);
        timer.sim_wait(100);
        CHECK(log_test(&spkr, satcat5::log::WARNING) > 0);
        timer.sim_wait(100);
        CHECK(log_test(&spkr, satcat5::log::INFO) > 0);
        timer.sim_wait(100);
        CHECK(log_test(&spkr, satcat5::log::DEBUG) == 0);
        // Confirm cooldown=0 disables output.
        timer.sim_wait(100);
        beep.set_cooldown(0);
        CHECK(log_test(&spkr, satcat5::log::CRITICAL) == 0);
    }
}
