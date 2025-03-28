//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for UDP dispatch and related blocks

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/ip_stack.h>
#include <satcat5/udp_socket.h>
#include <vector>

using satcat5::ip::ADDR_BROADCAST;
using satcat5::ip::ADDR_NONE;
using satcat5::udp::PORT_CFGBUS_CMD;
using satcat5::udp::PORT_CFGBUS_ACK;
using satcat5::udp::PORT_NONE;

TEST_CASE("UDP-socket") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Network communication infrastructure.
    satcat5::test::CrosslinkIp xlink(__FILE__);

    // Shortcuts and aliases:
    const auto MAC_CONTROLLER(xlink.MAC0);
    const auto MAC_PERIPHERAL(xlink.MAC1);
    const satcat5::ip::Addr IP_PERIPHERAL(xlink.IP1);
    const satcat5::ip::Addr IP_MULTICAST(224, 0, 0, 123);
    auto& c2p(xlink.eth0);              // Bad packet injection point
    auto& net_controller(xlink.net0);   // IP stack for controller (eth0)

    // Socket at each end of network link.
    satcat5::udp::Socket uut_controller(&xlink.net0.m_udp);
    satcat5::udp::Socket uut_peripheral(&xlink.net1.m_udp);

    // From idle state, neither Socket should be ready to communicate.
    CHECK_FALSE(uut_controller.ready_tx());
    CHECK_FALSE(uut_peripheral.ready_tx());
    CHECK_FALSE(uut_controller.ready_rx());
    CHECK_FALSE(uut_peripheral.ready_rx());

    SECTION("accessors") {
        CHECK(net_controller.m_ip.arp() == net_controller.m_udp.arp());
        CHECK(net_controller.m_ip.iface() == &net_controller.m_eth);
        CHECK(net_controller.m_ip.ipaddr() == net_controller.m_udp.ipaddr());
        CHECK(net_controller.m_ip.macaddr() == net_controller.m_udp.macaddr());
        CHECK(net_controller.m_ip.reply_ip() == net_controller.m_udp.reply_ip());
        CHECK(net_controller.m_ip.reply_mac() == net_controller.m_udp.reply_mac());
        uut_controller.connect(IP_PERIPHERAL, MAC_PERIPHERAL, PORT_CFGBUS_CMD, PORT_CFGBUS_ACK);
        CHECK(uut_controller.dstaddr() == IP_PERIPHERAL);
        CHECK(uut_controller.dstmac() == MAC_PERIPHERAL);
        CHECK(uut_controller.dstport() == PORT_CFGBUS_CMD);
        CHECK(uut_controller.gateway() == ADDR_NONE);
        CHECK(uut_controller.srcport() == PORT_CFGBUS_ACK);
    }

    SECTION("basic") {
        // Setup a one-way connection.
        uut_controller.connect(IP_PERIPHERAL, PORT_CFGBUS_CMD);
        uut_peripheral.bind(PORT_CFGBUS_CMD);   // Listening port
        // Execute ARP handshake.
        CHECK_FALSE(uut_controller.ready_tx());
        CHECK_FALSE(uut_peripheral.ready_tx());
        CHECK(uut_controller.ready_rx());
        CHECK(uut_peripheral.ready_rx());
        satcat5::poll::service_all();
        CHECK(uut_controller.dstmac() == MAC_PERIPHERAL);
        CHECK(uut_controller.ready_tx());
        CHECK_FALSE(uut_peripheral.ready_tx());
        CHECK(uut_controller.ready_rx());
        CHECK(uut_peripheral.ready_rx());
        // Send and receive a small UDP datagram.
        uut_controller.write_u32(0x12345678u);
        CHECK(uut_controller.write_finalize());
        satcat5::poll::service_all();
        CHECK(uut_peripheral.read_u32() == 0x12345678u);
        // Close the connection.
        uut_controller.close();
        CHECK_FALSE(uut_controller.ready_tx());
        CHECK_FALSE(uut_controller.ready_rx());
    }

    SECTION("connect-none") {
        // Attempt connection to a null address.
        uut_controller.connect(ADDR_NONE, PORT_CFGBUS_CMD);
        CHECK_FALSE(uut_controller.ready_tx());
        CHECK(uut_controller.ready_rx());
        // Confirm no ARP request was sent.
        satcat5::poll::service_all();
        CHECK(xlink.eth0.tx_count() == 0);
        CHECK(xlink.eth1.tx_count() == 0);
    }

    SECTION("full") {
        // Keep auto-binding local ports until the entire space is full.
        // (Dynamic allocation up to SATCAT5_UDP_MAXDYN sockets. Default
        //  is 16384, but we reduce this for unit-testing purposes.)
        std::vector<satcat5::udp::Socket*> bigvec(SATCAT5_UDP_MAXDYN, 0);
        unsigned ready_count = 0;
        for (auto a = bigvec.begin() ; a != bigvec.end() ; ++a) {
            // Specify MAC address so socket is ready to operate immediately.
            *a = new satcat5::udp::Socket(&net_controller.m_udp);
            (*a)->connect(IP_PERIPHERAL, MAC_PERIPHERAL, PORT_CFGBUS_CMD);
            if ((*a)->ready_rx() && (*a)->ready_tx()) ++ready_count;
        }
        // CHECK at the end to reduce Catch2 verbosity in debug mode.
        CHECK(ready_count == bigvec.size());
        // The next attempt to auto-bind should fail.
        log.suppress("Ports full");         // Suppress warning message...
        uut_controller.connect(IP_PERIPHERAL, MAC_PERIPHERAL, PORT_CFGBUS_CMD);
        CHECK_FALSE(uut_controller.ready_rx());
        CHECK(log.contains("Ports full"));  // ...but confirm it was sent.
        // Cleanup.
        for (auto a = bigvec.begin() ; a != bigvec.end() ; ++a) {
            delete *a;
        }
        // Try again; should succeed.
        uut_controller.connect(IP_PERIPHERAL, MAC_PERIPHERAL, PORT_CFGBUS_CMD);
        CHECK(uut_controller.ready_rx());   // No longer full -> Success!
    }

    SECTION("raw-rx") {
        // Setup Rx-only socket on the client.
        uut_peripheral.bind(satcat5::udp::Port{63419});
        // Inject a reference UDP datagram
        // (Source: Random VPN traffic captured using Wireshark.)
        c2p.write_obj(MAC_PERIPHERAL);      // Destination MAC
        c2p.write_obj(MAC_CONTROLLER);      // Source MAC
        c2p.write_u16(0x0800);              // Ethertype = IPv4
        c2p.write_u64(0x450000e4ba060000);  // Captured IP header
        c2p.write_u64(0x35110477ce753624);
        c2p.write_u32(0xc0a8014a);
        c2p.write_u64(0x1194f7bb00d00000);  // Captured UDP header
        c2p.write_u64(0x85aaff140005c816);  // Data starts here
        c2p.write_u64(0x6fbc681780c31e3f);
        c2p.write_u64(0xbe9418513b5b52b3);
        c2p.write_u64(0x8f3a1632c454626f);
        c2p.write_u64(0xed1e64f298ae1994);
        c2p.write_u64(0xde7a0fdef782c1cd);
        c2p.write_u64(0xc0adeb39e417c21a);
        c2p.write_u64(0xa4b5b6c295e1a541);
        c2p.write_u64(0x5fce6a519f3e56f0);
        c2p.write_u64(0xffb635dff90d1301);
        c2p.write_u64(0x6521b284b36691dd);
        c2p.write_u64(0x3a86914f5c30e7a3);
        c2p.write_u64(0x85852c8b7e2fab65);
        c2p.write_u64(0x15395b54065dd0a1);
        c2p.write_u64(0x25aee54b55443edd);
        c2p.write_u64(0xfadc3c810d13257d);
        c2p.write_u64(0x6d9f88df2c60431e);
        c2p.write_u64(0x6ab872e14c7f54c4);
        c2p.write_u64(0xc9d4b2eb535bd113);
        c2p.write_u64(0xea6f682eb1ca2110);
        c2p.write_u64(0xa72905f65af8e012);
        c2p.write_u64(0xb3e429fd5c2e7089);
        c2p.write_u64(0xe18e2dd5433749c5);
        c2p.write_u64(0x071f4c54e795c845);
        c2p.write_u64(0xdd93785f11fea01f);
        CHECK(c2p.write_finalize());
        // Confirm data received successfully.
        satcat5::poll::service_all();
        REQUIRE(uut_peripheral.get_read_ready() == 200);
        CHECK(uut_peripheral.read_u64() == 0x85aaff140005c816);
        CHECK(uut_peripheral.read_u64() == 0x6fbc681780c31e3f);
        CHECK(uut_peripheral.read_u64() == 0xbe9418513b5b52b3);
        CHECK(uut_peripheral.read_u64() == 0x8f3a1632c454626f);
        CHECK(uut_peripheral.read_u64() == 0xed1e64f298ae1994);
        CHECK(uut_peripheral.read_u64() == 0xde7a0fdef782c1cd);
        CHECK(uut_peripheral.read_u64() == 0xc0adeb39e417c21a);
        CHECK(uut_peripheral.read_u64() == 0xa4b5b6c295e1a541);
        CHECK(uut_peripheral.read_u64() == 0x5fce6a519f3e56f0);
        CHECK(uut_peripheral.read_u64() == 0xffb635dff90d1301);
        CHECK(uut_peripheral.read_u64() == 0x6521b284b36691dd);
        CHECK(uut_peripheral.read_u64() == 0x3a86914f5c30e7a3);
        CHECK(uut_peripheral.read_u64() == 0x85852c8b7e2fab65);
        CHECK(uut_peripheral.read_u64() == 0x15395b54065dd0a1);
        CHECK(uut_peripheral.read_u64() == 0x25aee54b55443edd);
        CHECK(uut_peripheral.read_u64() == 0xfadc3c810d13257d);
        CHECK(uut_peripheral.read_u64() == 0x6d9f88df2c60431e);
        CHECK(uut_peripheral.read_u64() == 0x6ab872e14c7f54c4);
        CHECK(uut_peripheral.read_u64() == 0xc9d4b2eb535bd113);
        CHECK(uut_peripheral.read_u64() == 0xea6f682eb1ca2110);
        CHECK(uut_peripheral.read_u64() == 0xa72905f65af8e012);
        CHECK(uut_peripheral.read_u64() == 0xb3e429fd5c2e7089);
        CHECK(uut_peripheral.read_u64() == 0xe18e2dd5433749c5);
        CHECK(uut_peripheral.read_u64() == 0x071f4c54e795c845);
        CHECK(uut_peripheral.read_u64() == 0xdd93785f11fea01f);
    }

    SECTION("reply") {
        // Create a raw udp::Address object on the client.
        satcat5::udp::Address addr(&xlink.net1.m_udp);
        satcat5::io::Writeable* wr = 0;
        // Send and receive a small UDP datagram from the server.
        // (No one is listening, so suppress the ICMP warning.)
        log.suppress("Destination port unreachable");
        uut_controller.connect(IP_PERIPHERAL, PORT_CFGBUS_CMD);
        uut_controller.write_u32(0x12345678u);
        CHECK(uut_controller.write_finalize());
        satcat5::poll::service_all();
        // Use the saved reply address to send a message.
        CHECK_FALSE(xlink.net1.m_udp.reply_is_multicast());
        CHECK_FALSE(addr.matches_reply_address());
        addr.save_reply_address();
        CHECK(addr.matches_reply_address());
        REQUIRE((wr = addr.open_write(4)));
        wr->write_u32(0xDEADBEEFu);
        CHECK(wr->write_finalize());
        // Confirm the reply is received by the server.
        satcat5::poll::service_all();
        CHECK(uut_controller.read_u32() == 0xDEADBEEFu);
    }

    SECTION("runt-rx") {
        // Setup Rx-only socket on the client.
        uut_peripheral.bind(satcat5::udp::Port{63419});
        // Inject a truncated version of the same datagram.
        // (Length in IP header is correct, but not the one in UDP header.)
        c2p.write_obj(MAC_PERIPHERAL);      // Destination MAC
        c2p.write_obj(MAC_CONTROLLER);      // Source MAC
        c2p.write_u16(0x0800);              // Ethertype = IPv4
        c2p.write_u64(0x4500002cba060000);  // Modified IP header...
        c2p.write_u64(0x3511052Fce753624);
        c2p.write_u32(0xc0a8014a);
        c2p.write_u64(0x1194f7bb00d00000);  // Captured UDP header
        c2p.write_u64(0x85aaff140005c816);  // Not enough data...
        c2p.write_u64(0x6fbc681780c31e3f);
        CHECK(c2p.write_finalize());
        // Confirm bad packet was rejected.
        satcat5::poll::service_all();
        CHECK(uut_peripheral.get_read_ready() == 0);
    }

    SECTION("error-unicast") {
        // Setup Tx unicast with no Rx.
        uut_controller.connect(IP_PERIPHERAL, PORT_CFGBUS_CMD);
        // Execute ARP handshake.
        satcat5::poll::service_all();
        CHECK(uut_controller.ready_tx());
        CHECK(uut_controller.ready_rx());
        // Sending the UDP datagram should produce an ICMP error message.
        log.suppress("Destination port unreachable");
        uut_controller.write_u32(0x12345678u);
        CHECK(uut_controller.write_finalize());
        satcat5::poll::service_all();
        CHECK(log.contains("Destination port unreachable"));
    }

    SECTION("error-broadcast") {
        // Setup Tx broadcast with no Rx.
        uut_controller.connect(ADDR_BROADCAST, PORT_CFGBUS_CMD);
        // No ARP handshake required.
        CHECK(uut_controller.ready_tx());
        CHECK(uut_controller.ready_rx());
        // Sending the UDP datagram should NOT produce an ICMP error,
        // because unhandled broadcast packets must be ignored.
        uut_controller.write_u32(0x12345678u);
        CHECK(uut_controller.write_finalize());
        satcat5::poll::service_all();
        CHECK_FALSE(log.contains("Destination port unreachable"));
    }

    SECTION("lost-arp") {
        // Tamper with the first ARP response during link setup.
        xlink.eth1.write_str("BadHeader");
        uut_controller.connect(IP_PERIPHERAL, PORT_CFGBUS_CMD);
        // Attempt to execute ARP handshake.
        satcat5::poll::service_all();
        CHECK_FALSE(uut_controller.ready_tx());
        CHECK(uut_controller.ready_rx());
        // Second ARP handshake should succeed.
        uut_controller.reconnect();
        satcat5::poll::service_all();
        CHECK(uut_controller.ready_tx());
        CHECK(uut_controller.ready_rx());
    }

    SECTION("macaddr") {
        // Setup a one-way connection with a known MAC address.
        uut_controller.connect(
            IP_PERIPHERAL, MAC_PERIPHERAL, PORT_CFGBUS_CMD);
        uut_peripheral.bind(PORT_CFGBUS_CMD);   // Listening port
        // No ARP query required.
        CHECK(uut_controller.ready_tx());
        CHECK(uut_controller.ready_rx());
        // Send and receive a small UDP datagram.
        uut_controller.write_u32(0x12345678u);
        CHECK(uut_controller.write_finalize());
        satcat5::poll::service_all();
        CHECK(uut_peripheral.read_u32() == 0x12345678u);
    }

    SECTION("broadcast") {
        // Setup a UDP broadcast.
        uut_controller.connect(ADDR_BROADCAST, PORT_CFGBUS_CMD);
        uut_peripheral.bind(PORT_CFGBUS_CMD);   // Listening port
        // No ARP query required.
        CHECK(uut_controller.ready_tx());
        CHECK(uut_controller.ready_rx());
        // Send and receive a small UDP datagram.
        uut_controller.write_u32(0x12345678u);
        CHECK(uut_controller.write_finalize());
        satcat5::poll::service_all();
        CHECK(uut_peripheral.read_u32() == 0x12345678u);
    }

    SECTION("multicast") {
        // Setup a UDP multicast.
        uut_controller.connect(IP_MULTICAST, PORT_CFGBUS_CMD);
        uut_peripheral.bind(PORT_CFGBUS_CMD);   // Listening port
        // No ARP query required.
        CHECK(uut_controller.ready_tx());
        CHECK(uut_controller.ready_rx());
        // Send and receive a small UDP datagram.
        uut_controller.write_u32(0x12345678u);
        CHECK(uut_controller.write_finalize());
        satcat5::poll::service_all();
        CHECK(uut_peripheral.read_u32() == 0x12345678u);
    }

    SECTION("throughput") {
        // Setup a one-way connection.
        uut_controller.connect(IP_PERIPHERAL, PORT_CFGBUS_CMD);
        uut_peripheral.bind(PORT_CFGBUS_CMD);   // Listening port
        // Execute ARP handshake.
        satcat5::poll::service_all();
        CHECK(uut_controller.ready_tx());
        CHECK(uut_controller.ready_rx());
        // Send and receive 125 packets, each 1000 bytes = 1 Mbit total
        satcat5::util::PosixTimer timer;
        auto tref = timer.now();
        for (unsigned a = 0 ; a < 125 ; ++a) {
            for (unsigned n = 0 ; n < 250 ; ++n)
                uut_controller.write_u32(satcat5::test::rand_u32());
            REQUIRE(uut_controller.write_finalize());
            satcat5::poll::service_all();
            REQUIRE(uut_peripheral.get_read_ready() == 1000);
            uut_peripheral.read_finalize();
        }
        // Report elapsed time.
        unsigned elapsed = tref.elapsed_usec();
        printf("UDP throughput: 1 Mbit / %u usec = %.1f Mbps\n",
            elapsed, 1e6f / elapsed);
    }
}
