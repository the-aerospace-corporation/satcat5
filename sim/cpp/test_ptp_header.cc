//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for "ptp::Header" and related classes.

#include <hal_test/catch.hpp>
#include <satcat5/io_core.h>
#include <satcat5/ptp_header.h>

using satcat5::ptp::ClockInfo;
using satcat5::ptp::Header;
using satcat5::ptp::PortId;
using satcat5::ptp::DEFAULT_CLOCK;
using satcat5::ptp::VERY_GOOD_CLOCK;

bool equal(const Header& a, const Header& b) {
    return (a.type == b.type)
        && (a.version == b.version)
        && (a.length == b.length)
        && (a.domain == b.domain)
        && (a.sdo_id == b.sdo_id)
        && (a.flags == b.flags)
        && (a.correction == b.correction)
        && (a.subtype == b.subtype)
        && (a.src_port == b.src_port)
        && (a.seq_id == b.seq_id)
        && (a.control == b.control)
        && (a.log_interval == b.log_interval);
}

bool equal(const ClockInfo& a, const ClockInfo& b) {
    return (a.grandmasterPriority1 == b.grandmasterPriority1)
        && (a.grandmasterClass == b.grandmasterClass)
        && (a.grandmasterAccuracy == b.grandmasterAccuracy)
        && (a.grandmasterVariance == b.grandmasterVariance)
        && (a.grandmasterPriority2 == b.grandmasterPriority2)
        && (a.grandmasterIdentity == b.grandmasterIdentity)
        && (a.stepsRemoved == b.stepsRemoved)
        && (a.timeSource == b.timeSource);
}

TEST_CASE("ptp_header") {
    // Most tests need a buffer for write + readback.
    u8 buffer[256];
    satcat5::io::ArrayWrite wr(buffer, sizeof(buffer));

    SECTION("PortId") {
        // Write test values into the working buffer.
        const PortId TEST = {1234, 5678};
        wr.write_obj(TEST);
        REQUIRE(wr.write_finalize());
        satcat5::io::ArrayRead rd(buffer, wr.written_len());
        // Read and compare each one.
        PortId tmp;
        rd.read_obj(tmp);
        CHECK(tmp == TEST);
        CHECK(rd.get_read_ready() == 0);
    }

    SECTION("Header") {
        // Write test values into the working buffer.
        const Header TEST = {1, 2, 3, 4, 5, 6, 7, 8, {9, 10}, 11, 12, 13};
        wr.write_obj(TEST);
        REQUIRE(wr.write_finalize());
        satcat5::io::ArrayRead rd(buffer, wr.written_len());
        // Read and compare each one.
        Header tmp;
        rd.read_obj(tmp);
        CHECK(equal(tmp, TEST));
        CHECK(rd.get_read_ready() == 0);
    }

    SECTION("ClockInfo") {
        // Write test values into the working buffer.
        wr.write_obj(DEFAULT_CLOCK);
        wr.write_obj(VERY_GOOD_CLOCK);
        REQUIRE(wr.write_finalize());
        satcat5::io::ArrayRead rd(buffer, wr.written_len());
        // Read and compare each one.
        ClockInfo tmp;
        rd.read_obj(tmp);
        CHECK(equal(tmp, DEFAULT_CLOCK));
        rd.read_obj(tmp);
        CHECK(equal(tmp, VERY_GOOD_CLOCK));
        CHECK(rd.get_read_ready() == 0);
    }

    SECTION("ReadEmpty") {
        satcat5::io::ArrayRead rd(buffer, 0);
        ClockInfo tmp1;
        Header tmp2;
        PortId tmp3;
        CHECK_FALSE(tmp1.read_from(&rd));
        CHECK_FALSE(tmp2.read_from(&rd));
        CHECK_FALSE(tmp3.read_from(&rd));
    }
}
