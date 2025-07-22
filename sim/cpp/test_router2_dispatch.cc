//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the software-defined IPv4 router

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_socket.h>
#include <satcat5/port_adapter.h>
#include <satcat5/router2_deferfwd.h>
#include <satcat5/router2_dispatch.h>
#include <satcat5/udp_socket.h>

// Enable additional diagnostics?
static constexpr bool DEBUG_VERBOSE = false;

using satcat5::eth::ETYPE_CBOR_TLM;
using satcat5::eth::MACADDR_NONE;
using satcat5::udp::PORT_CBOR_TLM;

// Test plugin allows or blocks connectivity to specific ports.
class MaskPlugin : public satcat5::eth::PluginCore {
public:
    SATCAT5_PMASK_TYPE m_prohibit;
    MaskPlugin(satcat5::eth::SwitchCore* sw, unsigned port)
        : PluginCore(sw), m_prohibit(satcat5::eth::idx2mask(port)) {}
    void query(satcat5::eth::PluginPacket& pkt) override {
        pkt.dst_mask &= ~m_prohibit;
    }
};

TEST_CASE("router2_dispatch") {
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
        IP1(192, 168, 1, 1),    // Endpoint in subnet #1
        IP2(192, 168, 2, 2),    // Endpoint in subnet #2
        IP3(192, 168, 3, 3),    // Endpoint in subnet #3
        IP4(192, 168, 3, 4),    // Non-existent endpoint
        IP5(192, 168, 5, 5);    // Non-existent subnet

    // Buffers and an IP-stack for each simulated Ethernet endpoint.
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::EthernetEndpoint nic2(MAC2, IP2);
    satcat5::test::EthernetEndpoint nic3(MAC3, IP3);

    // Unit under test and its supporting subsystems.
    u8 buff[65536];
    satcat5::router2::Dispatch uut(buff, sizeof(buff));
    satcat5::router2::DeferFwdStatic<> fwd(&uut);
    satcat5::ip::Stack ipstack(
        MAC0, IP0, uut.get_local_wr(), uut.get_local_rd());
    uut.set_debug(&pcap);
    uut.set_defer_fwd(&fwd);
    uut.set_local_iface(&ipstack.m_ip);
    uut.set_offload(0);

    // Attach router ports to each simulated endpoint.
    // (Port numbering in the order added: Port #1 = "port1" = "nic1".)
    satcat5::port::MailAdapter port1(&uut, &nic1, &nic1);
    satcat5::port::MailAdapter port2(&uut, &nic2, &nic2);
    satcat5::port::MailAdapter port3(&uut, &nic3, &nic3);

    // Configure the routing tables in each device under test.
    // (Use a mixture of preset and unspecified MAC addresses.)
    nic1.route()->route_simple(IP0, 24);    // All except 192.168.1.* --> UUT
    nic2.route()->route_simple(IP0, 24);    // All except 192.168.2.* --> UUT
    nic3.route()->route_simple(IP0, 24);    // All except 192.168.3.* --> UUT
    ipstack.m_route.route_clear();          // Designated routes only:
    ipstack.m_route.route_static({IP1, 24}, IP1, MAC1, 1);
    ipstack.m_route.route_static({IP2, 24}, IP2, MACADDR_NONE, 2);
    ipstack.m_route.route_static({IP3, 24}, IP3, MACADDR_NONE, 3);

    // Optionally log the pre-test routing table.
    if (DEBUG_VERBOSE)
        satcat5::log::Log(satcat5::log::DEBUG).write_obj(ipstack.m_route);

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

    // Trigger various ICMP errors.
    SECTION("icmp-error") {
        log.suppress("Destination");
        satcat5::udp::Socket sock1(nic1.udp());
        satcat5::udp::Socket sock3(nic3.udp());
        // Try a non-existent host on a valid subnet.
        // (Attempt deferred forwarding but fail due to an ARP timeout.)
        sock1.connect(IP4, MAC0, PORT_CBOR_TLM);
        CHECK(satcat5::test::write(&sock1, "Undeliverable message #1."));
        timer.sim_wait(5000);
        CHECK(log.contains("Destination host unreachable"));
        // Try a non-existent subnet. (Fails immediately.)
        sock1.connect(IP5, MAC0, PORT_CBOR_TLM);
        CHECK(satcat5::test::write(&sock1, "Undeliverable message #2."));
        timer.sim_wait(5000);
        CHECK(log.contains("Destination network unreachable"));
        // Try a local connection on the same subnet.
        // (Sends an ICMP forwarding request and then times out.)
        sock3.connect(IP4, MAC0, PORT_CBOR_TLM);
        CHECK(satcat5::test::write(&sock3, "Undeliverable message #3."));
        timer.sim_wait(5000);
        CHECK(log.contains("Destination host unreachable"));
        // Try a connection to a prohibited subnet.
        MaskPlugin mask(&uut, 2);  // Prohibit connections to port 2.
        sock3.connect(IP2, MAC0, PORT_CBOR_TLM);
        CHECK(satcat5::test::write(&sock3, "Undeliverable message #4."));
        timer.sim_wait(5000);
        CHECK(log.contains("Destination unreachable"));
    }

    // Non-IPv4 traffic should be dropped.
    SECTION("non-ip") {
        satcat5::eth::Socket sock1(nic1.eth());
        satcat5::eth::Socket sock2(nic2.eth());
        sock1.connect(MAC2, ETYPE_CBOR_TLM);
        sock2.bind(ETYPE_CBOR_TLM);
        satcat5::poll::service_all();
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 2."));
        satcat5::poll::service_all();
        CHECK(sock2.get_read_ready() == 0);
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

    // Port-shutdown flags.
    SECTION("port-shdn") {
        log.suppress("Destination");
        satcat5::udp::Socket sock1(nic1.udp());
        satcat5::udp::Socket sock2(nic2.udp());
        sock1.connect(IP2, MAC0, PORT_CBOR_TLM);
        sock2.bind(PORT_CBOR_TLM);
        // First attempt should succeed.
        CHECK(satcat5::test::write(&sock1, "First message."));
        timer.sim_wait(5000);
        CHECK(satcat5::test::read(&sock2, "First message."));
        // Shutdown port 2 and try again.
        uut.port_disable(1u << 2);
        CHECK(satcat5::test::write(&sock1, "Second message."));
        timer.sim_wait(5000);
        CHECK(log.contains("Destination network unreachable"));
        // Re-enable port 2 and try again.
        uut.port_enable(1u << 2);
        CHECK(satcat5::test::write(&sock1, "Third message."));
        timer.sim_wait(5000);
        CHECK(satcat5::test::read(&sock2, "Third message."));
    }

    // Time-to-live (TTL) expired.
    SECTION("ttl-expired") {
        log.suppress("TTL expired");
        // Manually write out a packet with TTL = 0.
        nic1.wr()->write_u64(0xDEADBEEF0000DEAD);
        nic1.wr()->write_u64(0xBEEF111108004500);
        nic1.wr()->write_u64(0x0030000100000011);
        nic1.wr()->write_u64(0x3568C0A80101C0A8);
        nic1.wr()->write_u64(0x0303C0015A63001C);
        nic1.wr()->write_u64(0x00004D6573736167);
        nic1.wr()->write_u64(0x652066726F6D2031);
        nic1.wr()->write_u64(0x20746F20332E0000);
        nic1.wr()->write_finalize();
        // This should result in an ICMP error.
        satcat5::poll::service_all();
        CHECK(log.contains("TTL expired in transit"));
    }

    // Optionally log the post-test routing table.
    if (DEBUG_VERBOSE)
        satcat5::log::Log(satcat5::log::DEBUG).write_obj(ipstack.m_route);
}
