//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Unit tests for various classes defined in "satcat5/ip_core.h"
// Ordinary use is thoroughly covered by other tests; this file is mainly
// reserved for corner cases that are otherwise difficult to reach.

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ip_core.h>

using satcat5::ip::ADDR_BROADCAST;
using satcat5::ip::ADDR_LOOPBACK;
using satcat5::ip::ADDR_NONE;
using satcat5::ip::UDP_MULTICAST;

TEST_CASE("ip_addr") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::ip::Addr ADDR_EXAMPLE(192, 168, 0, 1);

    // Validate the various "is_xyz()" address ranges.
    SECTION("is_broadast") {
        CHECK(ADDR_BROADCAST.is_broadcast());
        CHECK_FALSE(ADDR_EXAMPLE.is_broadcast());
        CHECK_FALSE(ADDR_LOOPBACK.is_broadcast());
        CHECK_FALSE(ADDR_NONE.is_broadcast());
        CHECK_FALSE(UDP_MULTICAST.addr.is_broadcast());
    }

    SECTION("is_multicast") {
        CHECK(ADDR_BROADCAST.is_multicast());
        CHECK_FALSE(ADDR_EXAMPLE.is_multicast());
        CHECK_FALSE(ADDR_LOOPBACK.is_multicast());
        CHECK_FALSE(ADDR_NONE.is_multicast());
        CHECK(UDP_MULTICAST.addr.is_multicast());
    }

    SECTION("is_reserved") {
        CHECK_FALSE(ADDR_BROADCAST.is_reserved());
        CHECK_FALSE(ADDR_EXAMPLE.is_reserved());
        CHECK(ADDR_LOOPBACK.is_reserved());
        CHECK(ADDR_NONE.is_reserved());
        CHECK_FALSE(UDP_MULTICAST.addr.is_reserved());
    }

    SECTION("is_unicast") {
        CHECK_FALSE(ADDR_BROADCAST.is_unicast());
        CHECK(ADDR_EXAMPLE.is_unicast());
        CHECK(ADDR_LOOPBACK.is_unicast());
        CHECK_FALSE(ADDR_NONE.is_unicast());
        CHECK_FALSE(UDP_MULTICAST.addr.is_unicast());
    }

    SECTION("is_valid") {
        CHECK(ADDR_BROADCAST.is_valid());
        CHECK(ADDR_EXAMPLE.is_valid());
        CHECK(ADDR_LOOPBACK.is_valid());
        CHECK_FALSE(ADDR_NONE.is_valid());
        CHECK(UDP_MULTICAST.addr.is_valid());
    }
}

TEST_CASE("ip_mask") {
    // Basic tests for CIDR prefixes.
    SECTION("prefix") {
        CHECK(satcat5::ip::MASK_NONE.value  == 0x00000000u);
        CHECK(satcat5::ip::MASK_8.value     == 0xFF000000u);
        CHECK(satcat5::ip::MASK_16.value    == 0xFFFF0000u);
        CHECK(satcat5::ip::MASK_24.value    == 0xFFFFFF00u);
        CHECK(satcat5::ip::MASK_32.value    == 0xFFFFFFFFu);
        CHECK(satcat5::ip::cidr_prefix(23)  == 0xFFFFFE00u);
        for (unsigned a = 0 ; a <= 32 ; ++a) {
            CHECK(satcat5::ip::cidr_prefix(a) == satcat5::ip::Mask(a).value);
        }
    }
}

TEST_CASE("ip_header") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Note: This reference contains IPv4 header only, not contained data.
    constexpr u8 REF_HEADER1[] = {
        0x45, 0x00, 0x02, 0x0E, 0x21, 0x53, 0x00, 0x00,
        0x3F, 0x11, 0xA5, 0x08, 0xC0, 0xA8, 0x00, 0x01,
        0xC0, 0xA8, 0x32, 0x32};
    satcat5::io::ArrayRead ref1(REF_HEADER1, sizeof(REF_HEADER1));

    // Test that various reference-packet fields are parsed correctly.
    SECTION("accessors") {
        // Read the reference header.
        // Note use of `read_core` rather than `read_from`.
        satcat5::ip::Header hdr;
        REQUIRE(hdr.read_core(&ref1));
        // Check various accessors:
        CHECK(hdr.ver() == 4);
        CHECK(hdr.ihl() == 5);
        CHECK(hdr.len_total() == 526);
        CHECK(hdr.len_inner() == 506);
        CHECK(hdr.frg() == 0);
        CHECK(hdr.id() == 0x2153);
        CHECK(hdr.ttl() == 63);
        CHECK(hdr.proto() == 0x11);
        CHECK(hdr.chk() == 0xA508);
        CHECK(hdr.src() == satcat5::ip::Addr(192, 168, 0, 1));
        CHECK(hdr.dst() == satcat5::ip::Addr(192, 168, 50, 50));
    }

    // Test that the increment checksum updates correctly.
    SECTION("chk_incr") {
        // Example from RFC1624 Section 4.
        // (Contrived to generate an 0x0000 rollover.)
        satcat5::ip::Header hdr = {0, 0, 0, 0, 0, 0xDD2F};
        CHECK(hdr.chk() == 0xDD2F);
        hdr.chk_incr16(0x5555, 0x3285);
        CHECK(hdr.chk() == 0x0000);
        // Hand-verified example.
        hdr.chk_incr32(0x12345678u, 0x87654321u);
        CHECK(hdr.chk() == 0x9E25);
        // Identical input/output should produce no change.
        hdr.chk_incr16(0x1234, 0x1234);
        CHECK(hdr.chk() == 0x9E25);
        hdr.chk_incr32(0xDEADBEEF, 0xDEADBEEF);
        CHECK(hdr.chk() == 0x9E25);
    }

    // Test that a header without associated data reports an error.
    SECTION("length_check") {
        satcat5::ip::Header hdr;
        CHECK_FALSE(hdr.read_from(&ref1));
    }
}
