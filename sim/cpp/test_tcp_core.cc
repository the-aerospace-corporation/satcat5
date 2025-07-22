//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Unit tests for Header classes defined in "satcat5/tcp_core.h"

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/tcp_core.h>

TEST_CASE("tcp_header") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Note: Reference SYN+ACK packet with no contained data.
    // https://wiki.wireshark.org/SampleCaptures#tcp
    constexpr u8 REF_HEADER1[] = {
        0x07, 0xD0, 0x1E, 0xC3, 0xB1, 0x8A, 0x67, 0x5B,
        0x1F, 0xBC, 0x16, 0xD3, 0x80, 0x12, 0xFA, 0xF0,
        0x12, 0x15, 0x00, 0x00, 0x02, 0x04, 0x05, 0xB4,
        0x01, 0x01, 0x04, 0x02, 0x01, 0x03, 0x03, 0x07};
    satcat5::io::ArrayRead ref1(REF_HEADER1, sizeof(REF_HEADER1));

    // Test that various reference-packet fields are parsed correctly.
    SECTION("accessors") {
        // Read the reference header.
        satcat5::tcp::Header hdr;
        REQUIRE(hdr.read_from(&ref1));
        // Check various accessors:
        CHECK(hdr.src() == 2000);
        CHECK(hdr.dst() == 7875);
        CHECK(hdr.ihl() == 8);
        CHECK(hdr.chk() == 0x1215);
    }

    // Test that the increment checksum updates correctly.
    SECTION("chk_incr") {
        // Example from RFC1624 Section 4.
        // (Contrived to generate an 0x0000 rollover.)
        satcat5::tcp::Header hdr = {0, 0, 0, 0, 0, 0, 0, 0, 0xDD2F};
        CHECK(hdr.chk() == 0xDD2F);
        hdr.chk_incr16(0x5555, 0x3285);
        CHECK(hdr.chk() == 0x0000);
        // Hand-verified example.
        hdr.chk_incr32(0x12345678u, 0x87654321u);
        CHECK(hdr.chk() == 0x9E25);
        // Identical input/output should produce no change.
        hdr.chk_incr16(0x1234, 0x1234);
        CHECK(hdr.chk() == 0x9E25);
        hdr.chk_incr32(0xDEADBEEFu, 0xDEADBEEFu);
        CHECK(hdr.chk() == 0x9E25);
    }

    // Test that read_from + write_to clones the packet.
    SECTION("write_to") {
        // Clone the reference header.
        satcat5::tcp::Header hdr;
        REQUIRE(hdr.read_from(&ref1));
        satcat5::io::StreamBufferHeap buf;
        hdr.write_to(&buf);
        // Confirm the copy matches the original.
        CHECK(satcat5::test::read_equal(&ref1, &buf));
    }
}
