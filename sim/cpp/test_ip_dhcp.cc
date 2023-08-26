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
// Test cases for DHCP client and DHCP server

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ip_dhcp.h>
#include <satcat5/ip_stack.h>

using satcat5::eth::MacAddr;
using satcat5::io::PacketBufferHeap;
using satcat5::ip::Addr;
using satcat5::ip::ADDR_NONE;
using satcat5::ip::DhcpClient;
using satcat5::ip::DhcpId;
using satcat5::ip::DhcpPoolStatic;
using satcat5::ip::DhcpServer;
using satcat5::ip::DhcpState;
using satcat5::ip::MASK_24;
using satcat5::ip::Stack;

// Shortcut function for checking result from "count_leases".
static constexpr unsigned POOL_SIZE = 16;
bool check_leases(DhcpServer& server, unsigned expected) {
    unsigned free, taken;
    server.count_leases(free, taken);
    return (free == POOL_SIZE-expected) && (taken == expected);
}

static constexpr u32 ONE_DAY = 24 * 60 * 60;

TEST_CASE("DHCP") {
    // Test infrastructure.
    satcat5::test::FastPosixTimer clock;
    satcat5::test::TimerAlways timer;
    satcat5::log::ToConsole log;
    log.disable();  // Suppress console output

    // Network communication infrastructure.
    const MacAddr MAC_SERVER = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11};
    const MacAddr MAC_CLIENT = {0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22};
    const Addr IP_SERVER(192, 168, 1, 11);  // Static IP for server
    const Addr IP_STATIC(192, 168, 1, 12);  // Static IP for client, if applicable
    const Addr IP_BASE  (192, 168, 1, 16);  // Start of DHCP address pool
    const Addr IP_ROUTER(192, 168, 1, 92);  // Gateway for local subnet
    const Addr IP_GOOGLE(0x08080808);       // Google DNS server

    PacketBufferHeap c2p, p2c;
    Stack net_client(MAC_CLIENT, ADDR_NONE, &c2p, &p2c, &clock);
    Stack net_server(MAC_SERVER, IP_SERVER, &p2c, &c2p, &clock);

    // Units under test.
    DhcpPoolStatic<POOL_SIZE> address_pool(IP_BASE);
    DhcpClient client(&net_client.m_udp);
    DhcpServer server(&net_server.m_udp, &address_pool);

    // Basic handshake: discover / offer / request / ack
    SECTION("basic") {
        // Check initial conditions.
        CHECK(check_leases(server, 0));
        CHECK(client.status() == 0);
        CHECK(net_client.ipaddr() == ADDR_NONE);
        CHECK(net_client.macaddr() == MAC_CLIENT);

        // Run simulation for a few seconds.
        timer.sim_wait(10000);

        // Confirm lease assigned successfully.
        CHECK(check_leases(server, 1));
        CHECK(client.state() == DhcpState::BOUND);
        CHECK(client.status() > 0);
        CHECK(net_client.ipaddr() == IP_BASE);
        CHECK(net_client.macaddr() == MAC_CLIENT);
    }

    // Basic exchange with a custom client-ID.
    SECTION("client-id") {
        // Generate a 47-byte client ID.
        DhcpId id;
        id.id_len = 47;
        for (u8 a = 0 ; a < id.id_len ; ++a)
            id.id[a] = a + 1;

        // Configure client and server metadata.
        client.set_client_id(&id);
        server.set_dns(IP_GOOGLE);
        server.set_domain("satcat5");
        server.set_gateway({IP_ROUTER, MASK_24});

        // After a few seconds, confirm lease succeeded.
        timer.sim_wait(10000);
        CHECK(check_leases(server, 1));
        CHECK(client.state() == DhcpState::BOUND);
        CHECK(client.status() > 0);
        CHECK(net_client.ipaddr() == IP_BASE);
        CHECK(net_client.macaddr() == MAC_CLIENT);
    }

    // Test various DhcpPool functions.
    SECTION("pool") {
        Addr IP_FIN = Addr(IP_BASE.value + POOL_SIZE - 1);
        Addr IP_OOB = Addr(IP_BASE.value + POOL_SIZE);
        CHECK(address_pool.addr2idx(IP_BASE) == 0);
        CHECK(address_pool.addr2idx(IP_FIN) == POOL_SIZE-1);
        CHECK(address_pool.contains(IP_BASE));
        CHECK(address_pool.contains(IP_FIN));
        CHECK_FALSE(address_pool.contains(IP_OOB));
    }

    // Static IP-address.
    SECTION("static") {
        // Set static configuration.
        client.release(IP_STATIC);
        timer.sim_wait(10000);

        // Confirm the system never claimed a lease.
        CHECK(check_leases(server, 0));
        CHECK(client.state() == DhcpState::STOPPED);
        CHECK(client.status() == 0);
        CHECK(net_client.ipaddr() == IP_STATIC);
    }

    // Information request.
    SECTION("inform") {
        // Configure DHCP server metadata.
        server.set_dns(IP_GOOGLE);
        server.set_domain("satcat5");
        server.set_gateway({IP_ROUTER, MASK_24});

        // Make the request.
        client.inform(IP_STATIC);
        timer.sim_wait(10000);

        // Confirm the system never claimed a lease.
        CHECK(check_leases(server, 0));
        CHECK(client.state() == DhcpState::STOPPED);
        CHECK(client.status() == 0);
        CHECK(net_client.ipaddr() == IP_STATIC);

        // Confirm the local subnet is configured.
        CHECK(net_client.m_ip.route_lookup(IP_BASE) == IP_BASE);
        CHECK(net_client.m_ip.route_lookup(IP_GOOGLE) == IP_ROUTER);
    }

    // Manual release / renew cycle.
    SECTION("renew") {
        // Release from the INIT state.
        client.release();
        timer.sim_wait(5000);
        CHECK(check_leases(server, 0));
        CHECK(client.state() == DhcpState::STOPPED);
        CHECK(client.status() == 0);
        CHECK(net_client.ipaddr() == ADDR_NONE);

        // Renew from the INIT state.
        CHECK(client.status() == 0);
        client.renew();
        timer.sim_wait(5000);
        CHECK(check_leases(server, 1));
        CHECK(client.state() == DhcpState::BOUND);
        CHECK(client.status() > 0);
        CHECK(net_client.ipaddr() == IP_BASE);

        // Renew from the BOUND state (should reuse).
        client.renew();
        CHECK(client.state() == DhcpState::RENEWING);
        timer.sim_wait(5000);
        CHECK(check_leases(server, 1));
        CHECK(client.state() == DhcpState::BOUND);
        CHECK(client.status() > 0);
        CHECK(net_client.ipaddr() == IP_BASE);

        // Release from the BOUND state.
        client.release();
        timer.sim_wait(5000);
        CHECK(check_leases(server, 0));
        CHECK(client.state() == DhcpState::STOPPED);
        CHECK(client.status() == 0);
        CHECK(net_client.ipaddr() == ADDR_NONE);
    }

    // Renew but the original lease is invalid.
    SECTION("renew2") {
        // Get the initial lease.
        timer.sim_wait(10000);
        CHECK(check_leases(server, 1));
        CHECK(client.state() == DhcpState::BOUND);
        CHECK(client.status() > 0);
        CHECK(net_client.ipaddr() == IP_BASE);

        // Another client steals our lease.
        CHECK(server.request(ONE_DAY, IP_BASE) == IP_BASE);

        // A manual renew should end up with a new address.
        client.renew();
        timer.sim_wait(10000);
        CHECK(check_leases(server, 2));
        CHECK(client.state() == DhcpState::BOUND);
        CHECK(client.status() > 0);
        CHECK(net_client.ipaddr() == IP_BASE+1);
    }

    // Manual rebind by blocking the first REQUEST message.
    SECTION("rebind") {
        // Wait for initial handshake.
        timer.sim_wait(10000);
        CHECK(check_leases(server, 1));
        CHECK(client.state() == DhcpState::BOUND);
        CHECK(client.status() > 0);
        CHECK(net_client.ipaddr() == IP_BASE);

        // Request a renewal but block the REQUEST message.
        client.renew();
        c2p.clear();

        // Confirm the first attempt failed.
        CHECK(client.state() == DhcpState::RENEWING);
        timer.sim_wait(1000);
        CHECK(client.state() == DhcpState::RENEWING);

        // Confirm second attempt succeeds.
        timer.sim_wait(30000);
        CHECK(check_leases(server, 1));
        CHECK(client.state() == DhcpState::BOUND);
        CHECK(client.status() > 0);
        CHECK(net_client.ipaddr() == IP_BASE);
    }

    // Local request superseding an in-progress transaction.
    SECTION("reserve-mid") {
        // Wait for initial DISCOVER/OFFER exchange.
        timer.sim_wait(5000);
        // Local reservation for the same address should take priority.
        CHECK(server.request(ONE_DAY, IP_BASE) == IP_BASE);
        // Request should restart and eventually succeed.
        timer.sim_wait(15000);
        CHECK(check_leases(server, 2));
        CHECK(client.state() == DhcpState::BOUND);
        CHECK(client.status() > 0);
        CHECK(net_client.ipaddr() == IP_BASE+1);
    }

    // Local request for an out-of-bounds address.
    SECTION("reserve-oob") {
        CHECK(server.request(ONE_DAY, IP_GOOGLE).value == ADDR_NONE.value);
    }

    // Assign an IP that's taken by another endpoint.
    // (Eventually it should complete an automatic failover.)
    SECTION("squatter") {
        net_server.set_addr(IP_BASE);
        timer.sim_wait(20000);
        CHECK(check_leases(server, 2));
        CHECK(client.status() > 0);
        CHECK(net_client.ipaddr() == (IP_BASE+1));
    }

    // Force allocation to fail because all addresses are taken.
    SECTION("no-vacancy") {
        CHECK(check_leases(server, 0));
        for (unsigned a = 0 ; a < POOL_SIZE ; ++a)
            server.request(ONE_DAY);
        CHECK(check_leases(server, POOL_SIZE));
        timer.sim_wait(10000);
        CHECK(check_leases(server, POOL_SIZE));
        CHECK(client.status() == 0);
    }

    // Client should reject extremely short lease durations.
    SECTION("short-lease") {
        server.max_lease(15);   // Only 15 seconds!?
        timer.sim_wait(10000);
        CHECK(client.status() == 0);
    }
}
