//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the software-defined Ethernet switch

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_checksum.h>
#include <satcat5/eth_socket.h>
#include <satcat5/eth_switch.h>
#include <satcat5/eth_sw_cache.h>
#include <satcat5/eth_sw_vlan.h>
#include <satcat5/port_adapter.h>
#include <satcat5/udp_socket.h>

using satcat5::eth::ETYPE_CBOR_TLM;
using satcat5::eth::MACADDR_BROADCAST;
using satcat5::eth::VPOL_STRICT;
using satcat5::eth::VtagPolicy;

class TestPlugin : satcat5::eth::SwitchPlugin {
public:
    TestPlugin(satcat5::eth::SwitchCore* sw, bool divert)
        : SwitchPlugin(sw), m_divert(divert) {}

    bool query(PacketMeta& pkt) override {
        // Create a Reader object and log the contents of each packet.
        satcat5::io::MultiPacket::Reader rd(pkt.pkt);
        satcat5::log::Log(satcat5::log::INFO, "Packet contents").write(&rd);
        rd.read_finalize();
        // Divert this packet?
        if (m_divert) {
            m_switch->free_packet(pkt.pkt);
            return false;   // Tell SwitchCore we took the packet.
        } else {
            return true;    // Resume normal processing.
        }
    }

protected:
    bool m_divert;
};

TEST_CASE("eth_switch") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));

    // Define the MAC and IP address for each test device.
    const satcat5::eth::MacAddr
        MAC0 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}},
        MAC1 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}},
        MAC2 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x33, 0x33}},
        MAC3 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x33, 0x44}};
    const satcat5::ip::Addr
        IP0(192, 168, 0, 1),
        IP1(192, 168, 0, 2),
        IP2(192, 168, 0, 3),
        IP3(192, 168, 0, 4);

    // Buffers and an IP-stack for each simulated Ethernet endpoint.
    // (Two regular endpoints and one SLIP-encoded endpoint.)
    satcat5::test::TimerSimulation timer;
    satcat5::test::EthernetEndpoint nic0(MAC0, IP0);
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::SlipEndpoint     nic2(MAC2, IP2);

    // Simulate a UART rate-limit on the SLIP-encoded port.
    nic2.set_rate(921600);

    // Unit under test with MAC-address cache.
    satcat5::eth::SwitchCoreStatic<> uut;
    satcat5::eth::SwitchCache<> cache(&uut);
    uut.set_debug(&pcap);

    // Create switch ports connected to each simulated endpoint.
    // (Two regular ports and one SLIP-encoded port.)
    satcat5::port::MailAdapter port0(&uut, &nic0, &nic0);
    satcat5::port::MailAdapter port1(&uut, &nic1, &nic1);
    satcat5::port::SlipAdapter port2(&uut, &nic2, &nic2);

    // Attach a Layer-2 socket to each port.
    satcat5::eth::Socket sock0(nic0.eth());
    satcat5::eth::Socket sock1(nic1.eth());
    satcat5::eth::Socket sock2(nic2.eth());

    // Preload all MAC addresses.
    cache.mactbl_write(0, MAC0);
    cache.mactbl_write(1, MAC1);
    cache.mactbl_write(2, MAC2);

    // Configure the traffic-statistics filter.
    // (Use of ETYPE_CBOR_TLM is completely arbitrary; any EtherType
    //  that's not a part of the normal IPv4 stack is suitable.)
    uut.set_traffic_filter(ETYPE_CBOR_TLM.value);
    CHECK(uut.get_traffic_filter() == ETYPE_CBOR_TLM.value);

    // Send a few unicast packets.
    SECTION("basic") {
        CHECK(uut.get_traffic_count() == 0);
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.connect(MAC2, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock2.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 2."));
        CHECK(satcat5::test::write(&sock2, "Message from 2 to 0."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock0, "Message from 2 to 0."));
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1."));
        CHECK(satcat5::test::read(&sock2, "Message from 1 to 2."));
        CHECK(uut.get_traffic_count() == 3);
    }

    // Simple test with UDP packets.
    SECTION("udp") {
        satcat5::udp::Socket tx(nic0.udp());
        satcat5::udp::Socket rx(nic1.udp());
        rx.bind(satcat5::udp::PORT_CBOR_TLM);
        tx.connect(IP1, satcat5::udp::PORT_CBOR_TLM);
        satcat5::poll::service_all();
        CHECK(satcat5::test::write(&tx, "Message from 0 to 1."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&rx, "Message from 0 to 1."));
    }

    // Test the null-adapter.
    SECTION("null-adapter") {
        // Add a new port using the null-adapter.
        satcat5::port::NullAdapter port3(&uut);
        satcat5::ip::Stack stack(MAC3, IP3, &port3, &port3);
        // Try pinging one of the other ports.
        log.suppress("Ping:");
        stack.m_ping.ping(IP0);
        timer.sim_wait(1000);
        CHECK(log.contains("Ping: Reply from = 192.168.0.1"));
    }

    // Add ports until we exceed the design limit.
    SECTION("overflow") {
        log.suppress("overflow");
        std::vector<satcat5::port::MailAdapter*> ports;
        // We've already added three ports. Add more up to a total of 33.
        for (unsigned pcount = 4 ; pcount <= 33 ; ++pcount) {
            auto next = new satcat5::port::MailAdapter(&uut, &nic0, &nic0);
            ports.push_back(next);
            if (pcount > 32) {
                CHECK(uut.port_count() == 32);
                CHECK(log.contains("overflow"));
            } else {
                CHECK(uut.port_count() == pcount);
                CHECK_FALSE(log.contains("overflow"));
            }
        }
        // Cleanup.
        for (auto ptr = ports.begin(); ptr != ports.end() ; ++ptr) {
            delete *ptr;
        }
    }

    // Test the SwitchPlugin API with in normal mode.
    SECTION("plugin-normal") {
        log.disable();
        // Create the test plugin in never-divert mode.
        TestPlugin plugin(&uut, false);
        // Send a brief message.
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));
        // The contents should appear in the log and at the destination.
        satcat5::poll::service_all();
        CHECK(log.contains("DEADBEEF"));
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1."));
    }

    // Test the SwitchPlugin API in divert mode.
    SECTION("plugin-divert") {
        log.disable();
        // Create the test plugin in always-divert mode.
        TestPlugin plugin(&uut, true);
        // Send a brief message.
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));
        // The contents should appear in the log but not the destination.
        satcat5::poll::service_all();
        CHECK(log.contains("DEADBEEF"));
        CHECK(sock1.get_read_ready() == 0);;
    }

    // Test the promiscuous-port mode.
    SECTION("prom") {
        uut.set_promiscuous(2, true);
        CHECK(uut.get_traffic_count() == 0);
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock2.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1 and 2."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1 and 2."));
        CHECK(satcat5::test::read(&sock2, "Message from 0 to 1 and 2."));
        CHECK(uut.get_traffic_count() == 1);
    }

    // Send a few packets in VLAN mode.
    SECTION("vlan") {
        satcat5::eth::VlanTag tag42{42}, tag43{43}, tag44{44};
        // Configure the VLAN plugin, starting from an open configuration.
        satcat5::eth::SwitchVlan<> vlan(&uut, false);
        vlan.vlan_leave(42, 2);         // VID 42 connects port 0 and 1 only
        vlan.vlan_set_mask(43, 0);      // VID 43 connects port 0 and 2 only
        vlan.vlan_join(43, 0);          // (Clear all, rejoin specific ports.)
        vlan.vlan_join(43, 2);
        vlan.vlan_set_rate(44, satcat5::eth::VRATE_100MBPS);
        // Confirm VLAN settings.
        CHECK(vlan.vlan_get_mask(42) == 0xFFFFFFFBu);
        CHECK(vlan.vlan_get_mask(43) == 0x00000005u);
        CHECK(vlan.vlan_get_mask(44) == 0xFFFFFFFFu);
        // Require tags for all traffic on Port 0.
        vlan.vlan_set_port(VtagPolicy(0, satcat5::eth::VTAG_MANDATORY));
        // Send and receive a few packets on VID 42.
        // Note: Port 2 is not connected to this VID.
        sock0.connect(MACADDR_BROADCAST, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag42);
        sock1.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag42);
        sock2.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag42);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));    // Accept
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 0."));    // Accept
        CHECK(satcat5::test::write(&sock2, "Message from 2 to 0."));    // Reject
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock0, "Message from 1 to 0."));
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1."));
        CHECK(sock2.get_read_ready() == 0);
        // Send and receive a few packets on VID 43.
        // Note: Port 1 is not connected to this VID.
        sock0.connect(MAC2, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag43);
        sock1.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag43);
        sock2.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag43);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 2."));    // Accept
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 0."));    // Reject
        CHECK(satcat5::test::write(&sock2, "Message from 2 to 0."));    // Accept
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock0, "Message from 2 to 0."));
        CHECK(satcat5::test::read(&sock2, "Message from 0 to 2."));
        CHECK(sock1.get_read_ready() == 0);
        // Send and receive a few packets on VID 44.
        // (Rate limit is high enough all messages should go through.)
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag44);
        sock1.connect(MAC2, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag44);
        sock2.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag44);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));    // Accept
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 2."));    // Accept
        CHECK(satcat5::test::write(&sock2, "Message from 2 to 0."));    // Accept
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock0, "Message from 2 to 0."));
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1."));
        CHECK(satcat5::test::read(&sock2, "Message from 1 to 2."));
    }

    // Test VLAN prioritization.
    SECTION("vpriority") {
        // Start this VLAN test from a locked-down configuration.
        satcat5::eth::SwitchVlan<> vlan(&uut, true);
        vlan.vlan_join(42, 0);
        vlan.vlan_join(42, 1);
        vlan.vlan_join(42, 2);
        // Port 0 always includes full tags on every frame.
        // Port 1 only includes priority metadata in each tag.
        satcat5::eth::VlanTag tag_42{42};           // Default VID
        vlan.vlan_set_port(VtagPolicy(0, satcat5::eth::VTAG_MANDATORY));
        vlan.vlan_set_port(VtagPolicy(1, satcat5::eth::VTAG_PRIORITY, tag_42));
        vlan.vlan_set_port(VtagPolicy(2, satcat5::eth::VTAG_ADMIT_ALL));
        // Configure a simple back-and-forth test scenario.
        satcat5::eth::VlanTag tag_hi{0xE000 | 42};  // Priority + VID
        satcat5::eth::VlanTag tag_lo{0x2000};       // Priority only
        sock0.connect(MAC2, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag_hi);
        sock1.connect(MAC2, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag_lo);
        sock2.bind(ETYPE_CBOR_TLM);
        // Send some mixed priority messages, then check the output order.
        CHECK(satcat5::test::write(&sock0, "High priority 1."));
        CHECK(satcat5::test::write(&sock1, "Low priority 1."));
        CHECK(satcat5::test::write(&sock0, "High priority 2."));
        CHECK(satcat5::test::write(&sock1, "Low priority 2."));
        CHECK(satcat5::test::write(&sock0, "High priority 3."));
        CHECK(satcat5::test::write(&sock1, "Low priority 3."));
        timer.sim_wait(10);
        CHECK(port2.consistency());
        CHECK(satcat5::test::read(&sock2, "High priority 1."));
        CHECK(satcat5::test::read(&sock2, "High priority 2."));
        CHECK(satcat5::test::read(&sock2, "High priority 3."));
        CHECK(satcat5::test::read(&sock2, "Low priority 1."));
        CHECK(satcat5::test::read(&sock2, "Low priority 2."));
        CHECK(satcat5::test::read(&sock2, "Low priority 3."));
    }

    // Test VLAN rate-limiting.
    SECTION("vrate") {
        // Start this VLAN test from a locked-down configuration.
        satcat5::eth::SwitchVlan<> vlan(&uut, true);
        vlan.vlan_join(42, 0);
        vlan.vlan_join(42, 1);
        // Port 0 always includes full tags on every frame.
        // Port 1 only includes priority metadata in each tag.
        vlan.vlan_set_port(VtagPolicy(0, satcat5::eth::VTAG_MANDATORY));
        vlan.vlan_set_port(VtagPolicy(1, satcat5::eth::VTAG_PRIORITY));
        // Set a carefully calibrated rate limit for VID 42.
        // Each test message is 38 bytes (header + VTAG + contents).
        // Accumulate 50 tokens over 10 msec -> Enough for one message.
        vlan.vlan_set_rate(42, satcat5::eth::VlanRate(VPOL_STRICT, 40000, 10));
        // Configure a simple back-and-forth test scenario.
        satcat5::eth::VlanTag tag42{42};
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag42);
        sock1.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM, tag42);
        // The first message should be accepted (initial credit).
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));    // Accept
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1."));
        // The next message should be rejected (tokens depleted).
        timer.sim_wait(5);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));    // Reject
        satcat5::poll::service_all();
        CHECK(sock1.get_read_ready() == 0);
        // The next messages should be accepted (tokens recovered).
        timer.sim_wait(5);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));    // Accept
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1."));
    }
}
