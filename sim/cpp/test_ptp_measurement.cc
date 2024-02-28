//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for "ptp::Measurement" and "ptp::MeasurementCache"

#include <hal_test/catch.hpp>
#include <hal_test/ptp_clock.h>
#include <satcat5/ptp_measurement.h>

using satcat5::ptp::Header;
using satcat5::ptp::Measurement;
using satcat5::ptp::MeasurementCache;
using satcat5::ptp::Time;

TEST_CASE("ptp_measurement") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Test headers
    const Header hdr1 =     // Basic template
        {1, 2, 3, 4, 5, 6, 7, 8, {9, 10}, 11, 12, 13};
    const Header hdr2 =     // Same except messageType (1 -> 2)
        {2, 2, 3, 4, 5, 6, 7, 8, {9, 10}, 11, 12, 13};
    const Header hdr3 =     // Same except sequenceId (11 -> 42)
        {1, 2, 3, 4, 5, 6, 7, 8, {9, 10}, 42, 12, 13};
    Measurement test1 =     // Complete measurement
        {hdr1, Time(123), Time(234), Time(345), Time(456)};
    Measurement test2 =     // Incomplete measurement
        {hdr1, Time(0),   Time(234), Time(345), Time(456)};
    Measurement test3 =     // Taken from real-life capture
        {hdr1, Time(0x1EB, 0x255FAAF8, 0x0000),
               Time(0x1AD, 0x17764B76, 0xE8FA),
               Time(0x1AE, 0x013F5F38, 0x0000),
               Time(0x1EC, 0x3424810A, 0xB3A6)};

    SECTION("measurement") {
        CHECK(test1.match(hdr1, hdr1.src_port));
        CHECK(test1.match(hdr2, hdr2.src_port));
        CHECK_FALSE(test1.match(hdr3, hdr3.src_port));
        CHECK(test1.done());
        CHECK_FALSE(test2.done());
    }

    SECTION("logging") {
        log.suppress("LogTest");
        satcat5::log::Log(satcat5::log::INFO, "LogTest").write_obj(test1);
        CHECK(log.contains("LogTest"));
    }

    SECTION("cache") {
        // Empty cache.
        MeasurementCache uut;
        CHECK(uut.find(hdr1) == 0);
        CHECK(uut.find(hdr2) == 0);
        CHECK(uut.find(hdr3) == 0);
        // Insert one header.
        auto first = uut.push(hdr1);
        CHECK(uut.find(hdr1) == first);
        CHECK(uut.find(hdr2) == first);
        CHECK(uut.find(hdr3) == 0);
        // Insert another header.
        auto second = uut.push(hdr3);
        CHECK(uut.find(hdr1) == first);
        CHECK(uut.find(hdr2) == first);
        CHECK(uut.find(hdr3) == second);
    }

    SECTION("calculations") {
        CHECK(test1.mean_path_delay() == Time(111));
        CHECK(test2.mean_path_delay() == Time(172));
        CHECK(test3.mean_path_delay() == Time(20331857759824ll));
        CHECK(test1.offset_from_master() == Time(0));
        CHECK(test2.offset_from_master() == Time(61));
        CHECK(test3.offset_from_master() == Time(-4098859838596438ll));
        CHECK(test1.mean_link_delay() == Time(166));
        CHECK(test2.mean_link_delay() == Time(228));
        CHECK(test3.mean_link_delay() == Time(40887283964371ll));
    }

    SECTION("notifications") {
        // Set up a dummy tracking controller.
        // Network communication infrastructure.
        satcat5::util::PosixTimer timer;
        satcat5::ptp::SimulatedClock clock(125e6, 125e6);
        satcat5::ptp::TrackingController uut(&timer, &clock, 0);
        // Confirm event counts before and after the PTP callback.
        CHECK(clock.num_fine() == 1);
        uut.ptp_ready(test1);
        CHECK(clock.num_fine() == 2);
    }
}
