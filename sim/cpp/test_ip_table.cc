//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the IPv4 routing table

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ip_table.h>

using satcat5::eth::MACADDR_NONE;
namespace ip = satcat5::ip;

TEST_CASE("IP-Table") {
    // Simulation infrastructure
    SATCAT5_TEST_START;

    // Address constants.
    const satcat5::eth::MacAddr MAC_SELF = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11};
    const satcat5::eth::MacAddr MAC_LOCAL1 = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE};
    const satcat5::eth::MacAddr MAC_LOCAL2 = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFF};
    const ip::Addr IP_GATEWAY1 (192, 168, 1,   1);  // A router on the local subnet
    const ip::Addr IP_GATEWAY2 (192, 168, 1,   2);  // A router on the local subnet
    const ip::Addr IP_SELF     (192, 168, 1,  11);  // The device under test
    const ip::Addr IP_LOCAL1   (192, 168, 1,  12);  // Another local endpoint
    const ip::Addr IP_LOCAL2   (192, 168, 1,  13);  // Another local endpoint
    const ip::Addr IP_REMOTE1  (192, 168, 5, 123);  // A remote endpoint
    const ip::Addr IP_REMOTE2  (192, 168, 5, 123);  // A remote endpoint
    const ip::Subnet SUBNET_LOCAL = {IP_LOCAL1, ip::MASK_24};
    const ip::Subnet SUBNET_REMOTE = {IP_REMOTE1, ip::MASK_16};

    // Unit under test.
    ip::Table uut;

    // Basic router tests.
    SECTION("basic") {
        // Default is LAN mode (100% direct routes)
        CHECK(uut.route_lookup(IP_GATEWAY1).gateway == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY2).gateway == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == IP_LOCAL1);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == IP_LOCAL2);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == IP_REMOTE1);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == IP_REMOTE2);
        // SOHO-style LAN subnet, single WAN at IP_GATEWAY1
        uut.route_simple(IP_GATEWAY1, ip::MASK_24);
        CHECK(uut.route_lookup(IP_GATEWAY1).gateway == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY2).gateway == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == IP_LOCAL1);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == IP_LOCAL2);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == IP_GATEWAY1);
        // After calling route_clear(), all routes should be null.
        uut.route_clear();
        CHECK(uut.route_lookup(IP_GATEWAY1).gateway == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_GATEWAY2).gateway == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == ip::ADDR_NONE);
    }

    // Test both methods of setting the default route.
    SECTION("default") {
        uut.route_default(IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY1).gateway == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY2).gateway == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == IP_GATEWAY1);
        uut.route_static(ip::DEFAULT_ROUTE, IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_GATEWAY1).gateway == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_GATEWAY2).gateway == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == IP_GATEWAY2);
    }

    // Test the "flush" command on static and ephemeral routes.
    SECTION("flush") {
        uut.route_clear();
        // Load one static route with MAC, one without, and one cache entry.
        REQUIRE(uut.route_static({IP_LOCAL1, 32}, IP_LOCAL1, MAC_LOCAL1));
        REQUIRE(uut.route_static({IP_LOCAL2, 32}, IP_LOCAL2));
        REQUIRE(uut.route_cache(IP_SELF, MAC_SELF));
        REQUIRE(uut.route_cache(IP_LOCAL2, MAC_LOCAL2));
        // Confirm table contents.
        CHECK(uut.route_lookup(IP_LOCAL1).dstmac == MAC_LOCAL1);
        CHECK(uut.route_lookup(IP_LOCAL2).dstmac == MAC_LOCAL2);
        CHECK(uut.route_lookup(IP_SELF).dstmac   == MAC_SELF);
        // Flush table and check again.
        uut.route_flush();
        CHECK(uut.route_lookup(IP_LOCAL1).dstmac == MAC_LOCAL1);
        CHECK(uut.route_lookup(IP_LOCAL2).dstmac == MACADDR_NONE);
        CHECK(uut.route_lookup(IP_SELF).dstmac   == MACADDR_NONE);
    }

    // Test behavior with no default route.
    SECTION("no-default") {
        uut.route_default(ip::ADDR_NONE);
        CHECK_FALSE(uut.route_lookup(IP_LOCAL1).is_deliverable());
        CHECK_FALSE(uut.route_lookup(IP_LOCAL2).is_deliverable());
        CHECK_FALSE(uut.route_lookup(IP_REMOTE1).is_deliverable());
        CHECK_FALSE(uut.route_lookup(IP_REMOTE2).is_deliverable());
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == ip::ADDR_NONE);
        REQUIRE(uut.route_static(SUBNET_LOCAL, ip::ADDR_BROADCAST));
        CHECK(uut.route_lookup(IP_LOCAL1).is_deliverable());
        CHECK(uut.route_lookup(IP_LOCAL2).is_deliverable());
        CHECK_FALSE(uut.route_lookup(IP_REMOTE1).is_deliverable());
        CHECK_FALSE(uut.route_lookup(IP_REMOTE2).is_deliverable());
        CHECK_FALSE(uut.route_lookup(IP_LOCAL1).is_multicast());
        CHECK_FALSE(uut.route_lookup(IP_LOCAL2).is_multicast());
        CHECK_FALSE(uut.route_lookup(IP_REMOTE1).is_multicast());
        CHECK_FALSE(uut.route_lookup(IP_REMOTE2).is_multicast());
        CHECK(uut.route_lookup(IP_LOCAL1).is_unicast());
        CHECK(uut.route_lookup(IP_LOCAL2).is_unicast());
        CHECK_FALSE(uut.route_lookup(IP_REMOTE1).is_unicast());
        CHECK_FALSE(uut.route_lookup(IP_REMOTE2).is_unicast());
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == IP_LOCAL1);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == IP_LOCAL2);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == ip::ADDR_NONE);
    }

    // Test prioritization of more specific routes.
    SECTION("priority") {
        uut.route_default(ip::ADDR_NONE);
        REQUIRE(uut.route_static(SUBNET_LOCAL,  IP_GATEWAY1)); // 192.168.1.*
        REQUIRE(uut.route_static(SUBNET_REMOTE, IP_GATEWAY2)); // 192.168.*.*
        CHECK(SUBNET_LOCAL != SUBNET_REMOTE);
        CHECK(uut.route_lookup(ip::Addr(192,168,1,5)).gateway == IP_GATEWAY1);
        CHECK(uut.route_lookup(ip::Addr(192,168,1,9)).gateway == IP_GATEWAY1);
        CHECK(uut.route_lookup(ip::Addr(192,168,5,5)).gateway == IP_GATEWAY2);
        CHECK(uut.route_lookup(ip::Addr(192,168,5,9)).gateway == IP_GATEWAY2);
        CHECK(uut.route_lookup(ip::Addr(192,169,1,1)).gateway == ip::ADDR_NONE);
        CHECK(uut.route_lookup(ip::Addr(192,169,9,9)).gateway == ip::ADDR_NONE);
    }

    // Test removal of both static and cached routes.
    SECTION("remove") {
        uut.route_clear();
        REQUIRE(uut.route_static(SUBNET_LOCAL, IP_GATEWAY1));
        REQUIRE(uut.route_static(SUBNET_REMOTE, IP_GATEWAY2));
        REQUIRE(uut.route_cache(IP_SELF, MAC_SELF));
        CHECK(uut.route_lookup(IP_SELF).gateway     == IP_SELF);
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == IP_GATEWAY2);
        REQUIRE(uut.route_remove(SUBNET_LOCAL));    // Remove static
        REQUIRE(uut.route_remove(IP_SELF));         // Remove cached
        CHECK(uut.route_lookup(IP_SELF).gateway     == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == IP_GATEWAY2);
        CHECK_FALSE(uut.route_remove(IP_SELF));     // Already removed
    }

    // Test replacement of an existing route.
    SECTION("replace") {
        REQUIRE(uut.route_static(SUBNET_REMOTE, IP_GATEWAY1));
        CHECK(uut.route_lookup(IP_GATEWAY1).gateway == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY2).gateway == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == IP_GATEWAY1);
        REQUIRE(uut.route_static(SUBNET_REMOTE, IP_GATEWAY2));
        CHECK(uut.route_lookup(IP_GATEWAY1).gateway == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_GATEWAY2).gateway == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL1).gateway   == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL2).gateway   == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_REMOTE1).gateway  == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_REMOTE2).gateway  == IP_GATEWAY2);
    }

    // Test cache-table wraparound.
    SECTION("cache-wrap") {
        for (unsigned a = 0 ; a < 2*SATCAT5_ROUTING_TABLE ; ++a) {
            ip::Addr tmp(192, 168, 0, a);
            CHECK(uut.route_cache(tmp, (a & 1) ? MAC_LOCAL1 : MAC_LOCAL2));
        }
    }

    // Test routing-table overflow.
    SECTION("overflow") {
        for (unsigned a = 0 ; a < SATCAT5_ROUTING_TABLE ; ++a) {
            ip::Subnet subnet = {ip::Addr(192, 168, a + 1, 0), ip::MASK_24};
            CHECK(uut.route_static(subnet, (a&1) ? IP_GATEWAY1 : IP_GATEWAY2));
        }
        CHECK_FALSE(uut.route_static(SUBNET_REMOTE, IP_GATEWAY1));
    }

    // Logging functionality.
    SECTION("logging") {
        log.disable();          // Suppress console output during this test
        uut.route_static(SUBNET_LOCAL,  IP_LOCAL1, MAC_LOCAL1, 1, 0xBE);
        uut.route_static(SUBNET_REMOTE, IP_LOCAL2, MAC_LOCAL2, 2, 0xEF);
        satcat5::log::Log(satcat5::log::CRITICAL, "Test1234: ").write_obj(uut);
        CHECK(log.contains("Test1234: Static routes"));
        CHECK(log.contains("D: 0.0.0.0 / 0.0.0.0 is Local"));
        CHECK(log.contains("0: 192.168.1.0 / 255.255.255.0 to 192.168.1.12 = DE:AD:BE:EF:CA:FE, p1, fBE"));
        CHECK(log.contains("1: 192.168.0.0 / 255.255.0.0 to 192.168.1.13 = DE:AD:BE:EF:CA:FF, p2, fEF"));
    }
}
