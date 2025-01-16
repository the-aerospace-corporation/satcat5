//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the router's hardware-accelerated offload interface

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_router2_offload.h>
#include <hal_test/sim_utils.h>
#include <satcat5/port_adapter.h>
#include <satcat5/router2_dispatch.h>
#include <satcat5/router2_offload.h>
#include <satcat5/udp_socket.h>

using satcat5::io::Readable;
using satcat5::io::Writeable;
using satcat5::udp::PORT_CBOR_TLM;

TEST_CASE("router2_offload") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));

    // Define the MAC and IP address for each test device.
    const satcat5::eth::MacAddr
        MAC0 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00}},
        MAC1 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}},
        MAC2 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}},
        MAC3 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x33, 0x33}};
    const satcat5::ip::Addr
        IP0(192, 168, 0, 0),    // Router itself
        IP1(192, 168, 1, 1),    // Test subnet #1 (hardware)
        IP2(192, 168, 2, 2),    // Test subnet #2 (hardware)
        IP3(192, 168, 3, 3);    // Test subnet #3 (software)

    // Buffers and an IP-stack for each simulated Ethernet endpoint.
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::EthernetEndpoint nic2(MAC2, IP2);
    satcat5::test::EthernetEndpoint nic3(MAC3, IP3);

    // Router dispatch unit and its supporting subsystems.
    u8 buff[65536];
    satcat5::router2::Dispatch router(buff, sizeof(buff));
    satcat5::ip::Stack ipstack(
        MAC0, IP0, router.get_local_wr(), router.get_local_rd(), &timer);
    router.set_debug(&pcap);
    router.set_local_iface(&ipstack.m_ip);

    // Create hardware and software ports, including the unit under test.
    // (Port numbering in the order added: Port #1 = "port1" = "nic1".)
    const unsigned CFG_DEVADDR = 42;
    satcat5::test::MockOffload mock(CFG_DEVADDR);
    mock.add_port(&nic1, &nic1);
    mock.add_port(&nic2, &nic2);
    satcat5::router2::Offload uut(&mock, CFG_DEVADDR, &router, 2);
    satcat5::port::MailAdapter port3(&router, &nic3, &nic3);

    // Configure the routing tables in each device under test.
    nic1.route()->route_simple(IP0, 24);    // All except 192.168.1.* --> UUT
    nic2.route()->route_simple(IP0, 24);    // All except 192.168.2.* --> UUT
    nic3.route()->route_simple(IP0, 24);    // All except 192.168.3.* --> UUT
    ipstack.m_route.route_clear();          // Designated routes only:
    ipstack.m_route.route_static({IP1, 24}, IP1, MAC1, 1);
    ipstack.m_route.route_static({IP2, 24}, IP2, MAC2, 2);
    ipstack.m_route.route_static({IP3, 24}, IP3, MAC3, 3);

    // Port-to-port connectivity test with UDP.
    SECTION("basic") {
        satcat5::udp::Socket sock1(nic1.udp());
        satcat5::udp::Socket sock2(nic2.udp());
        satcat5::udp::Socket sock3(nic3.udp());
        sock1.connect(IP2, PORT_CBOR_TLM, PORT_CBOR_TLM);
        sock2.connect(IP3, PORT_CBOR_TLM, PORT_CBOR_TLM);
        sock3.connect(IP1, PORT_CBOR_TLM, PORT_CBOR_TLM);
        satcat5::poll::service_all();
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 2."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::write(&sock2, "Message from 2 to 3."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::write(&sock3, "Message from 3 to 1."));
        timer.sim_wait(10);
        CHECK(satcat5::test::read(&sock1, "Message from 3 to 1."));
        CHECK(satcat5::test::read(&sock2, "Message from 1 to 2."));
        CHECK(satcat5::test::read(&sock3, "Message from 2 to 3."));
    }

    // Drop a packet due to back-to-back writes (i.e., Tx still busy).
    // (Should be rare in real hardware, but our simulation polls slowly.)
    SECTION("drop") {
        satcat5::udp::Socket sock1(nic1.udp());
        satcat5::udp::Socket sock2(nic2.udp());
        sock1.connect(IP2, PORT_CBOR_TLM, PORT_CBOR_TLM);
        sock2.bind(PORT_CBOR_TLM);
        satcat5::poll::service_all();
        CHECK(satcat5::test::write(&sock1, "1st message should succeed."));
        CHECK(satcat5::test::write(&sock1, "2nd message should be dropped."));
        timer.sim_wait(10);
        CHECK(satcat5::test::read(&sock2, "1st message should succeed."));
        CHECK(sock2.get_read_ready() == 0);     // Dropped?
    }

    // Test the link-state register.
    SECTION("link_up") {
        CHECK(uut.link_shdn_hw() == 0);     // Hardware mask = Bits 0 + 1
        CHECK(uut.link_shdn_sw() == 0);     // Software mask = Bits 1 + 2
        mock.port_shdn(-1);                 // Put all ports in shutdown
        CHECK(uut.link_shdn_hw() == 0x03);  // Hardware mask = Bits 0 + 1
        CHECK(uut.link_shdn_sw() == 0x06);  // Software mask = Bits 1 + 2
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

    // Port-index and port-mask functions.
    SECTION("pmask") {
        CHECK(uut.port_index(0) == 1);
        CHECK(uut.port_index(1) == 2);
        CHECK(uut.port_mask(0) == 0x02);
        CHECK(uut.port_mask(1) == 0x04);
        CHECK(uut.port_mask_all() == 0x06);
    }

    // Load new packet-forwarding rules.
    // (No way to confirm outcome, but we can exercise the functions.)
    SECTION("rules") {
        uut.rule_allow(satcat5::router2::RULE_NOIP_ALL);
        uut.rule_block(satcat5::router2::RULE_NOIP_ALL);
    }
}
