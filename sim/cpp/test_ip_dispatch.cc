//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the Internet Protocol dispatcher and routing table

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ip_dispatch.h>

namespace ip = satcat5::ip;

TEST_CASE("IP-Dispatch") {
    // Simulation infrastructure
    SATCAT5_TEST_START;

    // Address constants.
    const satcat5::eth::MacAddr MAC_SELF = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11};
    const satcat5::eth::MacAddr MAC_LOCAL1 = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE};
    const ip::Addr IP_GATEWAY1 (192, 168, 1,   1);  // A router on the local subnet
    const ip::Addr IP_GATEWAY2 (192, 168, 1,   2);  // A router on the local subnet
    const ip::Addr IP_SELF     (192, 168, 1,  11);  // The device under test
    const ip::Addr IP_LOCAL1   (192, 168, 1,  12);  // Another local endpoint
    const ip::Addr IP_LOCAL2   (192, 168, 1,  13);  // Another local endpoint
    const ip::Addr IP_REMOTE1  (192, 168, 5, 123);  // A remote endpoint
    const ip::Addr IP_REMOTE2  (192, 168, 5, 123);  // A remote endpoint
    const ip::Subnet SUBNET_LOCAL = {IP_LOCAL1, ip::MASK_24};
    const ip::Subnet SUBNET_REMOTE = {IP_REMOTE1, ip::MASK_16};

    // Network communication infrastructure.
    satcat5::io::PacketBufferHeap tx, rx;
    satcat5::eth::Dispatch eth(MAC_SELF, &tx, &rx);
    ip::Table tbl;
    ip::Dispatch uut(IP_SELF, &eth, &tbl);

    // Runtime adjustment of IP-address.
    SECTION("change-ip") {
        CHECK(IP_SELF == ip::Addr(0xC0A8010B));
        CHECK(uut.ipaddr() == IP_SELF);
        uut.set_addr(IP_LOCAL1);
        CHECK(uut.ipaddr() == IP_LOCAL1);
    }

    // Runtime adjustment of MAC-address.
    SECTION("change-mac") {
        CHECK(uut.macaddr() == MAC_SELF);
        uut.set_macaddr(MAC_LOCAL1);
        CHECK(uut.macaddr() == MAC_LOCAL1);
    }

    // Basic router tests.
    SECTION("route-basic") {
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
    SECTION("route-default") {
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

    // Test removal of both static and cached routes.
    SECTION("route-remove") {
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
}
