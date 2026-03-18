//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the IGMP client and server

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_utils.h>
#include <satcat5/igmp_client.h>
#include <satcat5/igmp_server.h>
#include <satcat5/router2_stack.h>
#include <satcat5/udp_socket.h>

// Define the MAC and IP address for each test device.
static const satcat5::eth::MacAddr
    MAC0 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00}},
    MAC1 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}},
    MAC2 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}},
    MAC3 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x33, 0x33}};
static const satcat5::ip::Addr
    IP0(192, 168, 0, 0),    // Router itself
    IP1(192, 168, 1, 1),    // Endpoint in subnet #1
    IP2(192, 168, 2, 2),    // Endpoint in subnet #2
    IP3(192, 168, 3, 3),    // Endpoint in subnet #3
    MCAST1(224, 1, 1, 1),   // Multicast group #1
    MCAST2(224, 2, 2, 2);   // Multicast group #2
static const satcat5::udp::Port
    PORT1(1231),            // UDP port for MCAST1
    PORT2(1232);            // UDP port for MCAST2

TEST_CASE("igmp") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));

    // Buffers and an IP-stack for each simulated Ethernet endpoint.
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::EthernetEndpoint nic2(MAC2, IP2);
    satcat5::test::EthernetEndpoint nic3(MAC3, IP3);

    // Create the test router with a built-in IGMP server.
    // Use aggressive query rates: "10" = Query every 1.0 seconds.
    satcat5::router2::StackSoftware<> uut(MAC0, IP0);
    uut.router()->set_debug(&pcap);
    uut.igmp()->set_mdly(10, 10);
    CHECK(uut.igmp()->is_querier());

    // Attach router ports to each simulated endpoint.
    // (Port numbering in the order added: Port #1 = "port1" = "nic1".)
    satcat5::port::MailAdapter port1(uut.router(), &nic1, &nic1);
    satcat5::port::MailAdapter port2(uut.router(), &nic2, &nic2);
    satcat5::port::MailAdapter port3(uut.router(), &nic3, &nic3);

    // Configure the routing tables in each device under test.
    // (Use a mixture of preset and unspecified MAC addresses.)
    nic1.route()->route_simple(IP0, 24);    // All except 192.168.1.*
    nic2.route()->route_simple(IP0, 24);    // All except 192.168.2.*
    nic3.route()->route_simple(IP0, 24);    // All except 192.168.3.*
    uut.table()->route_clear();             // Designated routes only:
    uut.table()->route_static({IP1, 24}, IP1, MAC1, 1);
    uut.table()->route_static({IP2, 24}, IP2, MAC2, 2);
    uut.table()->route_static({IP3, 24}, IP3, MAC3, 3);

    // Create two sockets for each endpoint, but don't bind anything yet.
    satcat5::udp::Socket sock1a(nic1.udp()), sock1b(nic1.udp());
    satcat5::udp::Socket sock2a(nic2.udp()), sock2b(nic2.udp());
    satcat5::udp::Socket sock3a(nic3.udp()), sock3b(nic3.udp());

    // Basic test sequence.
    SECTION("basic") {
        // Bind three sockets to the same group.
        sock1a.connect(MCAST1, PORT1, PORT1);
        sock2a.connect(MCAST1, PORT1, PORT1);
        sock3a.connect(MCAST1, PORT1, PORT1);
        timer.sim_wait(100);
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x0E);
        // Send and receive a test message.
        CHECK(satcat5::test::write(&sock1a, "Test message #1"));
        timer.sim_wait(100);
        CHECK(sock1a.get_read_ready() == 0);
        CHECK(satcat5::test::read(&sock2a, "Test message #1"));
        CHECK(satcat5::test::read(&sock3a, "Test message #1"));
        // Have one socket leave the group.
        // (It will take a few iterations for the router to fully refresh.)
        sock2a.close();
        timer.sim_wait(5000);
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x0A);
        // Send and receive another test message.
        CHECK(satcat5::test::write(&sock1a, "Test message #2"));
        timer.sim_wait(100);
        CHECK(sock1a.get_read_ready() == 0);
        CHECK(sock2a.get_read_ready() == 0);
        CHECK(satcat5::test::read(&sock3a, "Test message #2"));
    }

    // IPv4 broadcast should not trigger an IGMP query.
    SECTION("bcast") {
        sock1a.connect(satcat5::ip::ADDR_BROADCAST, PORT1, PORT1);
        timer.sim_wait(100);
        CHECK(uut.igmp()->get_mask(satcat5::ip::ADDR_BROADCAST) == 0);
    }

    // Test election of an alternate querier.
    SECTION("elect") {
        // Send an IGMP query to the network from a lower IP address.
        constexpr u8 QUERY[] = {
            0x46, 0x00, 0x00, 0x24, 0x77, 0xb3, 0x00, 0x00, 0x01, 0x02, 0x0d, 0x1f,
            0xc0, 0x00, 0x00, 0x00, 0xe0, 0x00, 0x00, 0x01, 0x94, 0x04, 0x00, 0x00,
            0x11, 0x0a, 0xee, 0xeb, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00};
        auto wr = nic1.eth()->open_write(MAC0, satcat5::eth::ETYPE_IPV4);
        CHECK(satcat5::test::write(wr, sizeof(QUERY), QUERY));
        // This should force the unit under test out of query mode.
        timer.sim_wait(100);
        CHECK_FALSE(uut.igmp()->is_querier());
    }

    // Force usage of IGMPv1.
    SECTION("igmpv1") {
        uut.igmp()->force_version(1);
        // Bind three sockets to the same group.
        sock1a.connect(MCAST1, PORT1, PORT1);
        sock2a.connect(MCAST1, PORT1, PORT1);
        sock3a.connect(MCAST1, PORT1, PORT1);
        timer.sim_wait(100);
        // Flush and restart using IGMPv1 only.
        // Note: IGMPv1 cannot adjust MDLY, always uses default = 10.0 seconds.
        uut.igmp()->flush();
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x00);
        timer.sim_wait(20000);
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x0E);
    }

    // Force usage of IGMPv2.
    SECTION("igmpv2") {
        uut.igmp()->force_version(2);
        // Bind sockets to different groups.
        sock1a.connect(MCAST1, PORT1, PORT1);
        sock2a.connect(MCAST1, PORT1, PORT1);
        sock3a.connect(MCAST1, PORT1, PORT1);
        sock2b.connect(MCAST2, PORT2, PORT2);
        sock3b.connect(MCAST2, PORT2, PORT2);
        timer.sim_wait(100);
        // Flush and restart using IGMPv2 only.
        uut.igmp()->flush();
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x00);
        timer.sim_wait(2000);
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x0E);
        // Have one socket leave the group.
        // (It will take a few iterations for the router to fully refresh.)
        sock2a.close();
        timer.sim_wait(5000);
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x0A);
        // Send and receive another test message.
        CHECK(satcat5::test::write(&sock1a, "Test message #1"));
        timer.sim_wait(100);
        CHECK(sock1a.get_read_ready() == 0);
        CHECK(sock2a.get_read_ready() == 0);
        CHECK(satcat5::test::read(&sock3a, "Test message #1"));
    }

    // Test case with multiple multicast groups.
    SECTION("many") {
        // Bind all six sockets to different groups.
        sock1a.connect(MCAST1, PORT1, PORT1);
        sock2a.connect(MCAST1, PORT1, PORT1);
        sock3a.connect(MCAST1, PORT1, PORT1);
        sock1b.connect(MCAST2, PORT2, PORT2);
        sock2b.connect(MCAST2, PORT2, PORT2);
        sock3b.connect(MCAST2, PORT2, PORT2);
        timer.sim_wait(100);
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x0E);
        CHECK(uut.igmp()->get_mask(MCAST2) == 0x0E);
        // Send and receive a test message.
        CHECK(satcat5::test::write(&sock1a, "Test message #1"));
        CHECK(satcat5::test::write(&sock1b, "Test message #2"));
        timer.sim_wait(100);
        CHECK(sock1a.get_read_ready() == 0);
        CHECK(satcat5::test::read(&sock2a, "Test message #1"));
        CHECK(satcat5::test::read(&sock3a, "Test message #1"));
        CHECK(sock1b.get_read_ready() == 0);
        CHECK(satcat5::test::read(&sock2b, "Test message #2"));
        CHECK(satcat5::test::read(&sock3b, "Test message #2"));
        // Wait for a few rounds of IGMP queries.
        timer.sim_wait(2000);
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x0E);
        CHECK(uut.igmp()->get_mask(MCAST2) == 0x0E);
    }

    // Test handling of very long max-delay intervals.
    SECTION("mdly") {
        // Bind three sockets to the same group.
        sock1a.connect(MCAST1, PORT1, PORT1);
        sock2a.connect(MCAST1, PORT1, PORT1);
        sock3a.connect(MCAST1, PORT1, PORT1);
        timer.sim_wait(100);
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x0E);
        // Flush the IGMP state and start fresh, with a very long query interval.
        // Value 144 = 0x90 = 25.6 seconds per query (floating point mode).
        uut.igmp()->set_mdly(144, 144);
        uut.igmp()->flush();
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x00);
        timer.sim_wait(26000);
        CHECK(uut.igmp()->get_mask(MCAST1) == 0x0E);
    }
}
