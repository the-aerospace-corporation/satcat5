//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// Test cases for the Internet Protocol dispatcher and routing table

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ip_dispatch.h>

namespace ip = satcat5::ip;

TEST_CASE("IP-Dispatch") {
    satcat5::log::ToConsole log;
    satcat5::util::PosixTimer timer;

    // Address constants.
    const satcat5::eth::MacAddr MAC_SELF = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11};
    const ip::Addr IP_GATEWAY1 (192, 168, 1,   1);
    const ip::Addr IP_GATEWAY2 (192, 168, 1,   2);
    const ip::Addr IP_SELF     (192, 168, 1,  11);
    const ip::Addr IP_LOCAL    (192, 168, 1,  12);
    const ip::Addr IP_REMOTE   (192, 168, 5, 123);
    const ip::Subnet SUBNET_LOCAL = {IP_LOCAL, ip::MASK_24};
    const ip::Subnet SUBNET_REMOTE = {IP_REMOTE, ip::MASK_16};

    // Network communication infrastructure.
    satcat5::io::PacketBufferHeap tx, rx;
    satcat5::eth::Dispatch eth(MAC_SELF, &tx, &rx);
    ip::Dispatch uut(IP_SELF, &eth, &timer);

    // Basic tests for CIDR prefixes.
    SECTION("prefix") {
        CHECK(ip::MASK_NONE.value  == 0x00000000u);
        CHECK(ip::MASK_8.value     == 0xFF000000u);
        CHECK(ip::MASK_16.value    == 0xFFFF0000u);
        CHECK(ip::MASK_24.value    == 0xFFFFFF00u);
        CHECK(ip::MASK_32.value    == 0xFFFFFFFFu);
        CHECK(ip::cidr_prefix(23)  == 0xFFFFFE00u);
        for (unsigned a = 0 ; a <= 32 ; ++a) {
            CHECK(ip::cidr_prefix(a) == ip::Mask(a).value);
        }
    }

    // Runtime adjustment of IP-address.
    SECTION("change-ip") {
        CHECK(IP_SELF == ip::Addr(0xC0A8010B));
        CHECK(uut.ipaddr() == IP_SELF);
        uut.set_addr(IP_LOCAL);
        CHECK(uut.ipaddr() == IP_LOCAL);
    }

    // Basic router tests.
    SECTION("route-basic") {
        uut.route_simple(IP_GATEWAY1, ip::MASK_24);
        CHECK(uut.route_lookup(IP_GATEWAY1) == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY2) == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL)    == IP_LOCAL);
        CHECK(uut.route_lookup(IP_REMOTE)   == IP_GATEWAY1);
        uut.route_clear();
        CHECK(uut.route_lookup(IP_GATEWAY1) == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY2) == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL)    == IP_LOCAL);
        CHECK(uut.route_lookup(IP_REMOTE)   == IP_REMOTE);
    }

    // Test both methods of setting the default route.
    SECTION("route-default") {
        uut.route_default(IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY1) == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY2) == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_LOCAL)    == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_REMOTE)   == IP_GATEWAY1);
        uut.route_set(ip::DEFAULT_ROUTE, IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_GATEWAY1) == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_GATEWAY2) == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL)    == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_REMOTE)   == IP_GATEWAY2);
    }

    // Test behavior with no default route.
    SECTION("route-no-default") {
        uut.route_default(ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_GATEWAY1) == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_GATEWAY2) == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_LOCAL)    == ip::ADDR_NONE);
        CHECK(uut.route_lookup(IP_REMOTE)   == ip::ADDR_NONE);
        REQUIRE(uut.route_set(SUBNET_LOCAL, IP_SELF));
        CHECK(uut.route_lookup(IP_GATEWAY1) == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY2) == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL)    == IP_LOCAL);
        CHECK(uut.route_lookup(IP_REMOTE)   == ip::ADDR_NONE);
    }

    // Test prioritization of more specific routes.
    SECTION("route-priority") {
        uut.route_default(ip::ADDR_NONE);
        REQUIRE(uut.route_set(SUBNET_LOCAL,  IP_GATEWAY1)); // 192.168.1.*
        REQUIRE(uut.route_set(SUBNET_REMOTE, IP_GATEWAY2)); // 192.168.*.*
        CHECK(SUBNET_LOCAL != SUBNET_REMOTE);
        CHECK(uut.route_lookup(ip::Addr(192,168,1,5)) == IP_GATEWAY1);
        CHECK(uut.route_lookup(ip::Addr(192,168,1,9)) == IP_GATEWAY1);
        CHECK(uut.route_lookup(ip::Addr(192,168,5,5)) == IP_GATEWAY2);
        CHECK(uut.route_lookup(ip::Addr(192,168,5,9)) == IP_GATEWAY2);
        CHECK(uut.route_lookup(ip::Addr(192,169,1,1)) == ip::ADDR_NONE);
        CHECK(uut.route_lookup(ip::Addr(192,169,9,9)) == ip::ADDR_NONE);
    }

    // Test replacement of an existing route.
    SECTION("route-replace") {
        REQUIRE(uut.route_set(SUBNET_REMOTE, IP_GATEWAY1));
        CHECK(uut.route_lookup(IP_GATEWAY1) == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_GATEWAY2) == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_LOCAL)    == IP_GATEWAY1);
        CHECK(uut.route_lookup(IP_REMOTE)   == IP_GATEWAY1);
        REQUIRE(uut.route_set(SUBNET_REMOTE, IP_GATEWAY2));
        CHECK(uut.route_lookup(IP_GATEWAY1) == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_GATEWAY2) == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_LOCAL)    == IP_GATEWAY2);
        CHECK(uut.route_lookup(IP_REMOTE)   == IP_GATEWAY2);
    }

    // Test routing-table overflow.
    SECTION("route-overflow") {
        for (unsigned a = 0 ; a < SATCAT5_ROUTING_TABLE ; ++a) {
            ip::Subnet subnet = {ip::Addr(192, 168, a + 1, 0), ip::MASK_24};
            CHECK(uut.route_set(subnet, (a&1) ? IP_GATEWAY1 : IP_GATEWAY2));
        }
        CHECK_FALSE(uut.route_set(SUBNET_REMOTE, IP_GATEWAY1));
    }
}
