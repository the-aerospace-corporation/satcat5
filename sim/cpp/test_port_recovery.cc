//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the software-defined Recovery Subsytem (closely related to test_eth_switch.cc)

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_checksum.h>
#include <satcat5/eth_socket.h>
#include <satcat5/eth_sw_cache.h>
#include <satcat5/eth_sw_vlan.h>
#include <satcat5/eth_switch.h>
#include <satcat5/port_adapter.h>
#include <satcat5/port_recovery.h>
#include <satcat5/udp_socket.h>

TEST_CASE("port_recovery") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));

    // Define the MAC and IP address for each test device.
    const satcat5::eth::MacAddr
        MAC0 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}},
        MAC1 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}};
    const satcat5::ip::Addr
        IP0(192, 168, 0, 1),
        IP1(192, 168, 0, 2);

    // Buffers and an IP-stack for each simulated Ethernet endpoint.
    // (Two regular endpoints.)
    satcat5::test::TimerSimulation timer;
    satcat5::test::EthernetEndpoint nic0(MAC0, IP0);
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::io::PacketBufferHeap tx2, rx2;

    // Unit under test with MAC-address cache.
    satcat5::eth::SwitchCoreStatic<> sw;
    satcat5::eth::SwitchCache<> cache(&sw);
    sw.set_debug(&pcap);

    // Create switch ports connected to each simulated endpoint.
    satcat5::port::RecoveryIngress recovery_in(&sw);
    satcat5::port::MailAdapter port0(&sw, &nic0, &nic0);
    satcat5::port::MailAdapter port1(&sw, &nic1, &nic1);
    satcat5::port::MailAdapter port2(&sw, &tx2, &rx2);
    satcat5::port::RecoveryEgress recovery_eg(&port2);

    // Attach a Layer-2 socket to each port.
    satcat5::eth::Socket sock0(nic0.eth());
    satcat5::eth::Socket sock1(nic1.eth());

    // Preload all MAC addresses.
    cache.mactbl_write(0, MAC0);
    cache.mactbl_write(1, MAC1);

    // Configure the traffic-statistics filter.
    sw.set_traffic_filter(satcat5::eth::ETYPE_RECOVERY.value);
    CHECK(sw.get_traffic_filter() == satcat5::eth::ETYPE_RECOVERY.value);

    // Send a recovery packet through ingress pipeline
    SECTION("Send Recovery Packet") {
        CHECK(sw.get_traffic_count() == 0);
        sock0.connect(MAC1, satcat5::eth::ETYPE_RECOVERY, satcat5::eth::ETYPE_RECOVERY);
        sock1.connect(MAC0, satcat5::eth::ETYPE_RECOVERY, satcat5::eth::ETYPE_RECOVERY);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(recovery_in.read(), "Message from 0 to 1."));
        CHECK(sw.get_traffic_count() == 1);
    }

    // Test not recovery packet
    SECTION("Drop non-Recovery Packet") {
        CHECK(sw.get_traffic_count() == 0);
        sock0.connect(MAC1, satcat5::eth::ETYPE_CBOR_TLM, satcat5::eth::ETYPE_CBOR_TLM);
        sock1.connect(MAC0, satcat5::eth::ETYPE_CBOR_TLM, satcat5::eth::ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&sock0, "Message from 0 to 1."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&sock1, "Message from 0 to 1."));
        CHECK(recovery_in.read()->get_read_ready() == 0);
        CHECK(sw.get_traffic_count() == 0);
    }

    // Send a recovery packet down the egress pipeline
    SECTION("System sends Recovery Packet") {
        CHECK(sw.get_traffic_count() == 0);
        CHECK(satcat5::test::write(&recovery_eg, "Recovery Message."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&rx2, "Recovery Message."));
        CHECK(sw.get_traffic_count() == 0);
    }
}
