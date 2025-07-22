//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the software-defined Ethernet switch

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_checksum.h>
#include <satcat5/eth_plugin.h>
#include <satcat5/eth_socket.h>
#include <satcat5/eth_switch.h>
#include <satcat5/eth_sw_cache.h>
#include <satcat5/eth_sw_log.h>
#include <satcat5/eth_sw_vlan.h>
#include <satcat5/port_adapter.h>
#include <satcat5/udp_socket.h>

using satcat5::eth::ETYPE_CBOR_TLM;
using satcat5::eth::MACADDR_BROADCAST;
using satcat5::eth::PluginPacket;
using satcat5::eth::VPOL_DEMOTE;
using satcat5::eth::VPOL_STRICT;
using satcat5::eth::VtagPolicy;

// Test plugin with logging and passthrough/divert toggle.
class TestPlugin : satcat5::eth::PluginCore {
public:
    TestPlugin(satcat5::eth::SwitchCore* sw, bool divert)
        : PluginCore(sw), m_divert(divert), m_prev(nullptr) {}

    ~TestPlugin() {
        if (m_prev) m_switch->free_packet(m_prev);
    }

    void query(PluginPacket& pkt) override {
        // Create a Reader object and log the contents of each packet.
        satcat5::io::MultiPacket::Reader rd(pkt.pkt);
        satcat5::log::Log(satcat5::log::INFO, "Packet contents").write(&rd);
        rd.read_finalize();
        // Divert this packet?
        if (m_divert) {
            // Notify parent that we are claiming ownership.
            pkt.divert();
            // Delete the previous packet, if applicable.
            // (Plugins are not allowed to delete before returning.)
            if (m_prev) m_switch->free_packet(m_prev);
            m_prev = pkt.pkt;
        }
    }

protected:
    bool m_divert;
    satcat5::io::MultiPacket* m_prev;
};

// Test plugin that makes an illegal header change.
class BadPlugin : satcat5::eth::PluginCore {
public:
    BadPlugin(satcat5::eth::SwitchCore* sw)
        : PluginCore(sw) {}

    void query(PluginPacket& pkt) override {
        // Adding a VLAN tag changes the header length.
        // (Length changes are only allowed during egress.)
        pkt.adjust();
        pkt.hdr.vtag.value = 0x1234;
    }
};

// Test plugin that drops the packet during egress.
class DropPlugin : satcat5::eth::PluginPort {
public:
    DropPlugin(satcat5::eth::SwitchPort* port)
        : PluginPort(port) {}

    void egress(PluginPacket& pkt) override {
        pkt.dst_mask = 0;
    }
};

TEST_CASE("eth_switch") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));

    // Define the MAC and IP address for each test device.
    const satcat5::eth::MacAddr
        MAC0 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00}},
        MAC1 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}},
        MAC2 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}},
        MAC3 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x33, 0x33}},
        MAC4 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x44, 0x44}};
    const satcat5::ip::Addr
        IP0(192, 168, 0, 0),
        IP1(192, 168, 0, 1),
        IP2(192, 168, 0, 2),
        IP3(192, 168, 0, 3);

    // Buffers and an IP-stack for each simulated Ethernet endpoint.
    // (Two regular endpoints and one SLIP-encoded endpoint.)
    satcat5::test::TimerSimulation timer;
    satcat5::test::EthernetEndpoint nic0(MAC0, IP0);
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::SlipEndpoint     nic2(MAC2, IP2);

    // Simulate a UART rate-limit on the SLIP-encoded port.
    nic2.set_rate(921600);

    // Unit under test with MAC-address cache.
    satcat5::eth::SwitchCoreStatic<8192> uut;
    satcat5::eth::SwitchCache<16> cache(&uut);
    uut.set_debug(&pcap);

    // Install the packet-logging plugin.
    satcat5::io::PacketBufferHeap pktlog;
    satcat5::eth::SwitchLogWriter logwr(&pktlog);
    uut.add_log(&logwr);

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
        timer.sim_wait(100);
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
        timer.sim_wait(100);
        CHECK(satcat5::test::write(&tx, "Message from 0 to 1."));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&rx, "Message from 0 to 1."));
    }

    // Exercise packet logs using miss-as-broadcast controls.
    SECTION("cache-miss-log") {
        // Forward packet events to the human-readable log.
        log.suppress("PktLog");
        satcat5::eth::SwitchLogFormatter fmt(&pktlog, "PktLog");
        // Connect to a non-existent MAC address.
        sock0.connect(MAC4, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.bind(ETYPE_CBOR_TLM);
        // Cache-miss = Broadcast
        cache.set_miss_mask(satcat5::eth::PMASK_ALL);
        CHECK(satcat5::test::write(&sock0, "Broadcast packet."));
        timer.sim_wait(100);
        CHECK(log.contains("Delivered to: 0xFFFFFFFE"));
        CHECK(satcat5::test::read(&sock1, "Broadcast packet."));
        // Cache-miss = Drop
        cache.set_miss_mask(satcat5::eth::PMASK_NONE);
        CHECK(satcat5::test::write(&sock0, "Dropped packet."));
        timer.sim_wait(100);
        CHECK(log.contains("Dropped: No route"));
        CHECK(sock1.get_read_ready() == 0);
        // Disable the logging source.
        log.clear();
        uut.remove_log(&logwr);
        CHECK(satcat5::test::write(&sock0, "Un-logged packet."));
        timer.sim_wait(100);
        CHECK(log.empty());
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
        CHECK(log.contains("Ping: Reply from = 192.168.0.0"));
    }

    // Overflow the data buffer and the packet log.
    SECTION("overflow-data") {
        // Disable callbacks to prevent egress from the switch.
        port0.set_callback(nullptr);
        port1.set_callback(nullptr);
        port2.set_callback(nullptr);
        // Construct a large reference packet for the test.
        // (Small packets fill up egress queues before the main buffer.)
        satcat5::io::ArrayWriteStatic<2048> pkt;
        pkt.write_obj(MAC1);            // DstMAC
        pkt.write_obj(MAC0);            // SrcMAC
        pkt.write_obj(ETYPE_CBOR_TLM);  // EtherType
        satcat5::test::write_random_final(&pkt, 1000);
        // Send packets until the SwitchCore buffer overflows.
        // Note: Write directly to the port, not through the socket's buffer.
        while(satcat5::test::write(&port0, pkt.written_len(), pkt.buffer())) {
            timer.sim_wait(1);          // Allow switch to ingest each packet
            pktlog.clear();             // Flush "Delivered" log message
        }
        // The last logged packet event should be the overflow.
        log.suppress("PktLog");
        satcat5::eth::SwitchLogFormatter fmt(&pktlog, "PktLog");
        timer.sim_wait(1);
        CHECK(log.contains("Dropped: Overflow"));
    }

    // Add ports until we exceed the design limit.
    SECTION("overflow-port") {
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
        timer.sim_wait(100);
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
        timer.sim_wait(100);
        CHECK(log.contains("DEADBEEF"));
        CHECK(sock1.get_read_ready() == 0);;
    }

    // Test that header-length changes cause an error.
    SECTION("plugin-bad-len") {
        log.disable();
        // Attach the length-change plugin.
        BadPlugin plugin(&uut);
        // Send a brief message.
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));
        // The length-change should be detected.
        timer.sim_wait(100);
        CHECK(log.contains("Plugin changed header length."));
        CHECK(sock1.get_read_ready() == 0);;
    }

    // Test that packet drops during egress are handled correctly.
    SECTION("plugin-drop-egress") {
        // Attach the egress-drop plugin.
        DropPlugin plugin(&port1);
        // Send a brief message in each direction.
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 0."));
        // One of the two packets should be dropped.
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&sock0, "Message from 1 to 0."));
        CHECK(sock1.get_read_ready() == 0);;
    }

    // Disable a specific port.
    SECTION("port_enable") {
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.connect(MAC2, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock2.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        port2.port_enable(false);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 2."));
        CHECK(satcat5::test::write(&sock2, "Message from 2 to 0."));
        timer.sim_wait(100);
        CHECK(sock0.get_read_ready() == 0);
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1."));
        CHECK(sock2.get_read_ready() == 0);
    }

    // Flush data before it's written.
    SECTION("port_flush") {
        // Write some junk data and discard it.
        port0.write_str("Junk data delete me plz.");
        port0.port_flush();
        // Proceed with a conventional test.
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 0."));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&sock0, "Message from 1 to 0."));
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1."));
    }

    // Test the promiscuous-port mode.
    SECTION("prom") {
        uut.set_promiscuous(2, true);
        CHECK(uut.get_traffic_count() == 0);
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock2.connect(MAC0, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1 and 2."));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1 and 2."));
        CHECK(satcat5::test::read(&sock2, "Message from 0 to 1 and 2."));
        CHECK(uut.get_traffic_count() == 1);
    }

    // Test egress and ingress fault handling for invalid frame headers.
    SECTION("runt-egress-ingress") {
        sock0.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock1.bind(ETYPE_CBOR_TLM);
        // Inject a runt frame into the egress path.
        satcat5::io::MultiWriter wr(&uut);
        wr.write_u32(123456);
        wr.write_bypass(port1.get_egress());
        // Inject a runt frame into the ingress path.
        wr.write_u32(123456);
        wr.write_finalize();
        // Send a regular message to the same destination.
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));
        timer.sim_wait(100);
        // Only the second message should be received.
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1."));
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
        timer.sim_wait(100);
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
        timer.sim_wait(100);
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
        timer.sim_wait(100);
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
        // Continue the test in "demote" mode.
        // Same rate parameters, but reduce priority instead of dropping packets.
        vlan.vlan_set_rate(42, satcat5::eth::VlanRate(VPOL_DEMOTE, 40000, 10));
        CHECK(satcat5::test::write(&sock0, "Regular priority message."));
        CHECK(satcat5::test::write(&sock0, "Reduced priority message."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock1, "Regular priority message."));
        CHECK(satcat5::test::read(&sock1, "Reduced priority message."));
    }
}
