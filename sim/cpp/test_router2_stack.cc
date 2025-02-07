//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the all-in-one IPv4 router stack

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_router2_offload.h>
#include <hal_test/sim_utils.h>
#include <satcat5/port_adapter.h>
#include <satcat5/router2_stack.h>
#include <satcat5/udp_socket.h>

using satcat5::eth::MACADDR_NONE;
using satcat5::ip::ADDR_BROADCAST;
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
    IP4(192, 168, 3, 4),    // Non-existent endpoint
    IP5(192, 168, 5, 5);    // Non-existent subnet

TEST_CASE("router2_stack_gateware") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));

    // Buffers and an IP-stack for each simulated Ethernet endpoint.
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::EthernetEndpoint nic2(MAC2, IP2);
    satcat5::test::EthernetEndpoint nic3(MAC3, IP3);

    // Mockup the ConfigBus interface with two hardware ports.
    const unsigned CFG_DEVADDR = 42;
    satcat5::test::MockOffload mock(CFG_DEVADDR);
    mock.add_port(&nic1, &nic1);
    mock.add_port(&nic2, &nic2);

    // Create the unit under test.
    satcat5::router2::StackGateware<> uut(
        MAC0, IP0, &mock, CFG_DEVADDR, 2);
    uut.router()->set_debug(&pcap);

    // Attach the software-defined port.
    satcat5::port::MailAdapter port3(uut.router(), &nic3, &nic3);

    // Configure the routing tables in each device under test.
    // (Use a mixture of preset and unspecified MAC addresses.)
    nic1.route()->route_simple(IP0, 24);    // All except 192.168.1.* --> UUT
    nic2.route()->route_simple(IP0, 24);    // All except 192.168.2.* --> UUT
    nic3.route()->route_simple(IP0, 24);    // All except 192.168.3.* --> UUT
    uut.table()->route_clear();             // Designated routes only:
    uut.table()->route_static({IP1, 24}, IP1, MAC1, 1);
    uut.table()->route_static({IP2, 24}, IP2, MACADDR_NONE, 2);
    uut.table()->route_static({IP3, 24}, IP3, MACADDR_NONE, 3);

    // Port-to-port connectivity test with UDP.
    SECTION("basic") {
        satcat5::udp::Socket sock1(nic1.udp());
        satcat5::udp::Socket sock2(nic2.udp());
        satcat5::udp::Socket sock3(nic3.udp());
        // First step for each endpoint is ARP exchange with the router...
        sock1.connect(IP2, PORT_CBOR_TLM, PORT_CBOR_TLM);
        sock2.connect(IP3, PORT_CBOR_TLM, PORT_CBOR_TLM);
        sock3.connect(IP1, PORT_CBOR_TLM, PORT_CBOR_TLM);
        satcat5::poll::service_all();
        // ...so the router's ARP cache is already populated at this point.
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 2."));
        timer.sim_wait(10);
        CHECK(satcat5::test::write(&sock2, "Message from 2 to 3."));
        timer.sim_wait(10);
        CHECK(satcat5::test::write(&sock3, "Message from 3 to 1."));
        timer.sim_wait(10);
        CHECK(satcat5::test::read(&sock1, "Message from 3 to 1."));
        CHECK(satcat5::test::read(&sock2, "Message from 1 to 2."));
        CHECK(satcat5::test::read(&sock3, "Message from 2 to 3."));
    }

    // Deferred packet forwarding test.
    SECTION("defer") {
        satcat5::udp::Socket sock1(nic1.udp());
        satcat5::udp::Socket sock2(nic2.udp());
        satcat5::udp::Socket sock3(nic3.udp());
        sock2.bind(PORT_CBOR_TLM);
        sock3.bind(PORT_CBOR_TLM);
        // This time, endpoints get a preset MAC address, so the router's
        // ARP cache remains empty, forcing a deferred forward.
        sock1.connect(IP2, MAC0, PORT_CBOR_TLM);
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 2."));
        satcat5::poll::service_all();
        sock1.connect(IP3, MAC0, PORT_CBOR_TLM);
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 3."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock2, "Message from 1 to 2."));
        CHECK(satcat5::test::read(&sock3, "Message from 1 to 3."));
    }

    // Port-to-router and port-to-port pings.
    SECTION("ping") {
        log.suppress("Ping: Reply from");
        nic1.stack().m_ping.ping(IP0, 1);
        timer.sim_wait(5000);
        CHECK(log.contains("Ping: Reply from = 192.168.0.0"));
        nic1.stack().m_ping.ping(IP2, 1);
        timer.sim_wait(5000);
        CHECK(log.contains("Ping: Reply from = 192.168.2.2"));
    }
}

TEST_CASE("router2_stack_software") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));

    // Buffers and an IP-stack for each simulated Ethernet endpoint.
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::EthernetEndpoint nic2(MAC2, IP2);
    satcat5::test::EthernetEndpoint nic3(MAC3, IP3);

    // Create the unit under test.
    satcat5::router2::StackSoftware<> uut(MAC0, IP0);
    uut.router()->set_debug(&pcap);

    // Attach router ports to each simulated endpoint.
    // (Port numbering in the order added: Port #1 = "port1" = "nic1".)
    satcat5::port::MailAdapter port1(uut.router(), &nic1, &nic1);
    satcat5::port::MailAdapter port2(uut.router(), &nic2, &nic2);
    satcat5::port::MailAdapter port3(uut.router(), &nic3, &nic3);

    // Configure the routing tables in each device under test.
    // (Use a mixture of preset and unspecified MAC addresses.)
    nic1.route()->route_simple(IP0, 24);    // All except 192.168.1.* --> UUT
    nic2.route()->route_simple(IP0, 24);    // All except 192.168.2.* --> UUT
    nic3.route()->route_simple(IP0, 24);    // All except 192.168.3.* --> UUT
    uut.table()->route_clear();             // Designated routes only:
    uut.table()->route_static({IP1, 24}, IP1, MAC1, 1);
    uut.table()->route_static({IP2, 24}, IP2, MACADDR_NONE, 2);
    uut.table()->route_static({IP3, 24}, IP3, MACADDR_NONE, 3);

    // Port-to-port connectivity test with UDP.
    SECTION("basic") {
        satcat5::udp::Socket sock1(nic1.udp());
        satcat5::udp::Socket sock2(nic2.udp());
        satcat5::udp::Socket sock3(nic3.udp());
        // First step for each endpoint is ARP exchange with the router...
        sock1.connect(IP2, PORT_CBOR_TLM, PORT_CBOR_TLM);
        sock2.connect(IP3, PORT_CBOR_TLM, PORT_CBOR_TLM);
        sock3.connect(IP1, PORT_CBOR_TLM, PORT_CBOR_TLM);
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

    // Deferred packet forwarding test.
    SECTION("defer") {
        satcat5::udp::Socket sock1(nic1.udp());
        satcat5::udp::Socket sock2(nic2.udp());
        satcat5::udp::Socket sock3(nic3.udp());
        sock2.bind(PORT_CBOR_TLM);
        sock3.bind(PORT_CBOR_TLM);
        // This time, endpoints get a preset MAC address, so the router's
        // ARP cache remains empty, forcing a deferred forward.
        sock1.connect(IP2, MAC0, PORT_CBOR_TLM);
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 2."));
        satcat5::poll::service_all();
        sock1.connect(IP3, MAC0, PORT_CBOR_TLM);
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 3."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock2, "Message from 1 to 2."));
        CHECK(satcat5::test::read(&sock3, "Message from 1 to 3."));
    }

    // Port-to-router and port-to-port pings.
    SECTION("ping") {
        log.suppress("Ping: Reply from");
        nic1.stack().m_ping.ping(IP0, 1);
        timer.sim_wait(5000);
        CHECK(log.contains("Ping: Reply from = 192.168.0.0"));
        nic1.stack().m_ping.ping(IP2, 1);
        timer.sim_wait(5000);
        CHECK(log.contains("Ping: Reply from = 192.168.2.2"));
    }

    // Confirm port-number metadata is propagated by the MAC-address cache.
    SECTION("port_cache") {
        log.suppress("Ping: Reply from");
        // Reconfigure the network with a local subnet 192.168.1.*.
        const satcat5::ip::Addr ROUTER(192, 168, 1, 2);
        nic1.route()->route_simple(ROUTER);
        uut.set_ipaddr(ROUTER);
        uut.table()->route_clear();
        uut.table()->route_static({IP1, 24}, ADDR_BROADCAST, MACADDR_NONE, 1);
        uut.table()->route_static({IP2, 24}, IP2, MACADDR_NONE, 2);
        uut.table()->route_static({IP3, 24}, IP3, MACADDR_NONE, 3);
        // Send a ping request from NIC1 to the router.
        // (This should trigger the ARP query and update the router cache.)
        nic1.stack().m_ping.ping(ROUTER, 1);
        timer.sim_wait(5000);
        CHECK(log.contains("Ping: Reply from = 192.168.1.2"));
        // Confirm the contents of the router's ARP cache.
        auto route = uut.table()->route_lookup(IP1);
        CHECK(route.port == 1);
    }
}
