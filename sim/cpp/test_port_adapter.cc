//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Edge-cases for the classes in "port_adapter.h".
// More typical cases are covered in "test_eth_switch.cc".

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_socket.h>
#include <satcat5/eth_sw_cache.h>
#include <satcat5/eth_switch.h>
#include <satcat5/port_adapter.h>

using satcat5::eth::ETYPE_CBOR_TLM;

TEST_CASE("port_adapter") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));
    satcat5::test::TimerSimulation timer;

    // Define the MAC and IP address for each test device.
    const satcat5::eth::MacAddr
        MAC1 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}},
        MAC2 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}};
    const satcat5::ip::Addr
        IP1(192, 168, 0, 1),
        IP2(192, 168, 0, 2);

    // Buffers and an IP-stack for each simulated Ethernet endpoint.
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::EthernetEndpoint nic2(MAC2, IP2);

    // Instantiate two crosslinked Ethernet switches.
    satcat5::eth::SwitchCoreStatic<> switch_a;
    satcat5::eth::SwitchCoreStatic<> switch_b;
    satcat5::eth::SwitchCache<> cache_a(&switch_a);
    satcat5::eth::SwitchCache<> cache_b(&switch_b);
    switch_a.set_debug(&pcap);
    switch_b.set_debug(&pcap);
    satcat5::port::MailAdapter port1(&switch_a, &nic1, &nic1);
    satcat5::port::MailAdapter port2(&switch_b, &nic2, &nic2);
    satcat5::port::SwitchAdapter xlink(&switch_a, &switch_b);

    // Attach a Layer-2 socket to each port.
    satcat5::eth::Socket sock1(nic1.eth());
    satcat5::eth::Socket sock2(nic2.eth());

    // Send a few unicast packets.
    SECTION("basic") {
        sock1.connect(MAC2, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        sock2.connect(MAC1, ETYPE_CBOR_TLM, ETYPE_CBOR_TLM);
        CHECK(satcat5::test::write(&sock1, "Message from 1 to 2."));
        CHECK(satcat5::test::write(&sock2, "Message from 2 to 1."));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&sock1, "Message from 2 to 1."));
        CHECK(satcat5::test::read(&sock2, "Message from 1 to 2."));
    }
}
