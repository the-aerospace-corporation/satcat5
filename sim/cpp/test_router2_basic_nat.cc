//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the Basic-NAT plugin

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_utils.h>
#include <satcat5/router2_basic_nat.h>
#include <satcat5/router2_stack.h>
#include <satcat5/udp_socket.h>

using satcat5::eth::MACADDR_NONE;
using satcat5::udp::PORT_CBOR_TLM;

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
    IP4(192, 168, 4, 1),    // Translation from IP1
    IP5(192, 168, 5, 2),    // Translation from IP2
    IP6(192, 168, 6, 3);    // Translation from IP3

TEST_CASE("router2_basic_nat") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));

    // Buffers and an IP-stack for each simulated Ethernet endpoint.
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::EthernetEndpoint nic2(MAC2, IP2);
    satcat5::test::EthernetEndpoint nic3(MAC3, IP3);

    // Create router and attach ports to each simulated endpoint.
    // (Port numbering in the order added: Port #1 = "port1" = "nic1".)
    satcat5::router2::StackSoftware<> router(MAC0, IP0);
    router.router()->set_debug(&pcap);
    satcat5::port::MailAdapter port1(router.router(), &nic1, &nic1);
    satcat5::port::MailAdapter port2(router.router(), &nic2, &nic2);
    satcat5::port::MailAdapter port3(router.router(), &nic3, &nic3);

    // Attach the NAT plugin to each port.
    satcat5::router2::BasicNat uut1(&port1);
    satcat5::router2::BasicNat uut2(&port2);
    satcat5::router2::BasicNat uut3(&port3);
    uut1.config({IP1, 24}, {IP4, 24});
    uut2.config({IP2, 24}, {IP5, 24});
    uut3.config({IP3, 24}, {IP6, 24});

    // Configure the routing tables in each endpoint device.
    nic1.route()->route_simple(IP0, 24);    // All except 192.168.1.*
    nic2.route()->route_simple(IP0, 24);    // All except 192.168.2.*
    nic3.route()->route_simple(IP0, 24);    // All except 192.168.3.*

    // The router itself only sees translated addresses (4.*, 5.*, 6.*).
    router.table()->route_clear();          // No default route.
    router.table()->route_static({IP4, 24}, IP4, MACADDR_NONE, 1);
    router.table()->route_static({IP5, 24}, IP5, MACADDR_NONE, 2);
    router.table()->route_static({IP6, 24}, IP6, MACADDR_NONE, 3);

    // Port-to-port connectivity test with UDP.
    SECTION("udp") {
        satcat5::udp::Socket sock1(nic1.udp());
        satcat5::udp::Socket sock2(nic2.udp());
        satcat5::udp::Socket sock3(nic3.udp());
        // First step for each endpoint is ARP exchange with the router...
        sock1.connect(IP5, PORT_CBOR_TLM, PORT_CBOR_TLM);
        sock2.connect(IP6, PORT_CBOR_TLM, PORT_CBOR_TLM);
        sock3.connect(IP4, PORT_CBOR_TLM, PORT_CBOR_TLM);
        satcat5::poll::service_all();
        // ...so the router's ARP cache is already populated at this point.
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 2."));
        CHECK(satcat5::test::write(&sock2, "Message from 2 to 3."));
        CHECK(satcat5::test::write(&sock3, "Message from 3 to 1."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock1, "Message from 3 to 1."));
        CHECK(satcat5::test::read(&sock2, "Message from 1 to 2."));
        CHECK(satcat5::test::read(&sock3, "Message from 2 to 3."));
    }
}
