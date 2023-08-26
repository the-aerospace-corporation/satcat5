//////////////////////////////////////////////////////////////////////////
// Copyright 2022, 2023 The Aerospace Corporation
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
// Test cases for Ping utilities

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ip_stack.h>

TEST_CASE("Ping") {
    // Test infrastructure.
    satcat5::util::PosixTimer clock;
    satcat5::test::TimerAlways timer;
    satcat5::log::ToConsole log;
    log.disable();  // Always suppress console output

    // Network communication infrastructure.
    const satcat5::eth::MacAddr MAC_A = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11};
    const satcat5::eth::MacAddr MAC_B = {0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22};
    const satcat5::ip::Addr IP_A(192, 168, 1, 11);
    const satcat5::ip::Addr IP_B(192, 168, 1, 74);
    const satcat5::ip::Addr IP_C(192, 168, 1, 93);

    satcat5::io::PacketBufferHeap c2p, p2c;
    satcat5::ip::Stack net_a(MAC_A, IP_A, &c2p, &p2c, &clock);
    satcat5::ip::Stack net_b(MAC_B, IP_B, &p2c, &c2p, &clock);

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
