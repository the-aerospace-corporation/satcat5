//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for Ping utilities

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/ip_stack.h>

TEST_CASE("Ping") {
    // Test infrastructure.
    satcat5::test::TimerAlways timer;
    satcat5::log::ToConsole log;

    // Suppress expected log messages from the unit under test.
    log.suppress("Ping:");

    // Network communication infrastructure.
    satcat5::test::CrosslinkIp xlink;

    // Shortcuts and aliases:
    const satcat5::ip::Addr IP_A(xlink.IP0);
    const satcat5::ip::Addr IP_B(xlink.IP1);
    const satcat5::ip::Addr IP_C(192, 168, 1, 93);
    satcat5::ip::Stack& net_a(xlink.net0);

    // Sanity check that the three addresses are unique.
    REQUIRE(IP_A != IP_B);
    REQUIRE(IP_A != IP_C);
    REQUIRE(IP_B != IP_C);

    // Count ARP and ICMP responses.
    satcat5::test::CountArpResponse ctr_arp(&net_a.m_ip);
    satcat5::test::CountPingResponse ctr_icmp(&net_a.m_ip);

    SECTION("arp-simple") {
        // Command Host-A to arping Host-B.
        net_a.m_ping.arping(IP_B, 3);
        timer.sim_wait(500);    // Wait for 1st ping + response
        CHECK(log.contains("Reply from")); log.clear();
        timer.sim_wait(1000);   // Wait for 2nd ping + response
        CHECK(log.contains("Reply from")); log.clear();
        timer.sim_wait(1000);   // Wait for 3rd ping + response
        CHECK(log.contains("Reply from")); log.clear();
        timer.sim_wait(1000);   // Wait for 4th ping + response
        CHECK(log.empty());
    }

    SECTION("arp-badip") {
        // Attempt to arping a nonexistent address.
        net_a.m_ping.arping(IP_C, 1);
        timer.sim_wait(1500);   // Bad IP, no ARP response
        CHECK(log.contains("Request timed out"));
    }

    SECTION("icmp-simple") {
        // Command Host-A to ping Host-B.
        net_a.m_ping.ping(IP_B, 2);
        timer.sim_wait(500);    // Wait for ARP handshake...
        CHECK(log.empty());
        timer.sim_wait(1000);   // Wait for 1st ping + response
        CHECK(log.contains("Reply from")); log.clear();
        timer.sim_wait(1000);   // Wait for 2nd ping + response
        CHECK(log.contains("Reply from")); log.clear();
        timer.sim_wait(1000);   // Wait for 3rd ping + response
        CHECK(log.empty());
    }

    SECTION("icmp-badip") {
        // Attempt to ping a nonexistent address.
        net_a.m_ping.ping(IP_C, 2);
        timer.sim_wait(3500);   // Attempt ARP 3 times then abort
        CHECK(log.contains("Gateway unreachable"));
    }

    SECTION("gateway_change") {
        // Simulate a gateway-change event during an ARPING.
        net_a.m_ping.arping(IP_B, 1);
        net_a.m_ip.m_arp.gateway_change(IP_B, IP_C);
        // Confirm that we don't get any errors.
        CHECK(log.empty());
    }
}
