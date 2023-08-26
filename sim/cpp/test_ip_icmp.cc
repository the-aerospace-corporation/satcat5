//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// Test cases for the Internet Control Message Protocol (ICMP)

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/ip_address.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/ip_icmp.h>

// Mock IP sub-protocol that always triggers an ICMP error.
static const u8 PROTO_FAKE = 0xFF;

class FakeProto : public satcat5::net::Protocol
{
public:
    explicit FakeProto(satcat5::ip::Dispatch* iface)
        : satcat5::net::Protocol(satcat5::net::Type(PROTO_FAKE))
        , m_iface(iface)
    {
        m_iface->add(this);
    }

    ~FakeProto() {
        m_iface->remove(this);
    }

    // Send a "request" that will trigger the designated ICMP error type.
    bool request(satcat5::ip::Addr dst, u16 errtype, u32 arg = 0) {
        static const unsigned REQ_LEN = 6;      // Fixed request length
        satcat5::io::Writeable* wr = m_iface->open_write(
            satcat5::eth::MACADDR_BROADCAST, dst, PROTO_FAKE, REQ_LEN);
        wr->write_u16(errtype);                 // Requested ICMP type
        wr->write_u32(arg);                     // Optional argument
        return wr->write_finalize();            // Send the request
    }

protected:
    // Handle incoming frames by sending a "reply" with the designated error type.
    void frame_rcvd(satcat5::io::LimitedRead& src) override {
        u16 typ = src.read_u16();               // Read request type
        u32 arg = src.read_u32();               // Read request argument
        CHECK(m_iface->m_icmp.send_error(typ, &src, arg));
    }

    // Pointer to the parent interface.
    satcat5::ip::Dispatch* const m_iface;
};

TEST_CASE("ICMP") {
    satcat5::log::ToConsole log;
    satcat5::util::PosixTimer timer;

    // Network communication infrastructure.
    const satcat5::eth::MacAddr MAC_CONTROLLER = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11};
    const satcat5::eth::MacAddr MAC_PERIPHERAL = {0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22};
    const satcat5::ip::Addr IP_CONTROLLER(192, 168, 1, 11);
    const satcat5::ip::Addr IP_PERIPHERAL(192, 168, 1, 12);
    satcat5::io::PacketBufferHeap c2p, p2c;
    satcat5::eth::Dispatch eth_controller(MAC_CONTROLLER, &c2p, &p2c);
    satcat5::eth::Dispatch eth_peripheral(MAC_PERIPHERAL, &p2c, &c2p);
    satcat5::ip::Dispatch ip_controller(IP_CONTROLLER, &eth_controller, &timer);
    satcat5::ip::Dispatch ip_peripheral(IP_PERIPHERAL, &eth_peripheral, &timer);

    // Specialized test infrastructure
    FakeProto fake_controller(&ip_controller);
    FakeProto fake_peripheral(&ip_peripheral);

    // Open a connection and execute ARP handshake.
    satcat5::ip::Address addr(&ip_controller, satcat5::ip::PROTO_ICMP);
    addr.connect(IP_PERIPHERAL);
    satcat5::poll::service_all();
    REQUIRE(addr.iface() == &ip_controller);
    REQUIRE(addr.ready());

    // Issue ICMP requests from controller to peripheral.
    SECTION("ping") {
        satcat5::test::CountPingResponse event(&ip_controller);
        ip_controller.m_icmp.send_ping(addr);
        CHECK(event.count() == 0);
        satcat5::poll::service_all();
        CHECK(event.count() == 1);
    }

    SECTION("time") {
        ip_controller.m_icmp.send_timereq(addr);
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("Timestamp"));
    }

    // Test handling of an unsupported IP sub-protocol.
    SECTION("missing-proto") {
        // Write the frame manually so we can add some IP header options.
        c2p.write_obj(MAC_PERIPHERAL);              // MAC destination
        c2p.write_obj(MAC_CONTROLLER);              // MAC source
        c2p.write_obj(satcat5::eth::ETYPE_IPV4);    // EtherType
        c2p.write_u32(0x4F00004C);                  // IHL = 15 words (max)
        c2p.write_u32(0xCAFE0000);                  // ID + flags
        c2p.write_u32(0x424269D4);                  // Proto = 0x42, checksum
        c2p.write_u32(IP_CONTROLLER.value);         // IP Source
        c2p.write_u32(IP_PERIPHERAL.value);         // IP Destination
        for (unsigned a = 0 ; a < 14 ; ++a)         // 10x fake options
            c2p.write_u32(0x12340000 + a);          // +4x placeholder data
        CHECK(c2p.write_finalize());
        // Deliver the frame and watch for the error message.
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("Destination protocol unreachable"));
    }

    // Test handling of a bad IPv4 checksum.
    SECTION("ip-checksum") {
        // Same packet as in "missing-proto" but break the checksum.
        c2p.write_obj(MAC_PERIPHERAL);              // MAC destination
        c2p.write_obj(MAC_CONTROLLER);              // MAC source
        c2p.write_obj(satcat5::eth::ETYPE_IPV4);    // EtherType
        c2p.write_u32(0x4F00004C);                  // IHL = 15 words (max)
        c2p.write_u32(0xCAFE0000);                  // ID + flags
        c2p.write_u32(0x424269D3);                  // Checksum should be 0x69D4
        c2p.write_u32(IP_CONTROLLER.value);         // IP Source
        c2p.write_u32(IP_PERIPHERAL.value);         // IP Destination
        for (unsigned a = 0 ; a < 14 ; ++a)         // 10x fake options
            c2p.write_u32(0x12340000 + a);          // +4x placeholder data
        CHECK(c2p.write_finalize());
        // Deliver the frame and it should be dropped silently.
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.empty());
    }

    // Test ICMP message-sending and error-handling:
    //  * Controller asks peripheral to send it a specific error.
    //    (Using the special "FakeProto" test protocol defined above.)
    //  * Peripheral receives that request and sends the ICMP frame.
    //  * Controller receives and processes the ICMP frame.
    //  * If applicable, test confirms the logged error message.
    SECTION("redirect") {
        // Controller asks peripheral to send it an ICMP redirect.
        fake_controller.request(IP_PERIPHERAL,
            satcat5::ip::ICMP_REDIRECT_HOST, 0xDEADBEEF);
        satcat5::poll::service_all();
        // Confirm that the redirect took effect.
        CHECK(addr.dstaddr() == IP_PERIPHERAL);
        CHECK(addr.gateway().value == 0xDEADBEEF);
    }

    SECTION("reserved") {
        // Request a few undefined ICMP codes, which should all be ignored.
        fake_controller.request(IP_PERIPHERAL, 0x0103);     // Reserved
        fake_controller.request(IP_PERIPHERAL, 0x0207);     // Reserved
        fake_controller.request(IP_PERIPHERAL, 0x0400);     // Deprecated
        satcat5::poll::service_all();
        // Per RFC1122 Section 3.2.2: "If an ICMP message of unknown type
        // is received, it MUST be silently discarded."
        // https://datatracker.ietf.org/doc/html/rfc1122
        CHECK(log.empty());     // Silently discard per RFC11
    }

    SECTION("unreachable-prohibit") {
        fake_controller.request(IP_PERIPHERAL,
            satcat5::ip::ICMP_NET_PROHIBITED);
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("Destination unreachable"));
    }

    SECTION("unreachable-host") {
        fake_controller.request(IP_PERIPHERAL,
            satcat5::ip::ICMP_UNREACHABLE_HOST);
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("Destination host unreachable"));
    }

    SECTION("unreachable-net") {
        fake_controller.request(IP_PERIPHERAL,
            satcat5::ip::ICMP_UNREACHABLE_NET);
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("Destination network unreachable"));
    }

    SECTION("unreachable-host") {
        fake_controller.request(IP_PERIPHERAL,
            satcat5::ip::ICMP_UNREACHABLE_HOST);
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("Destination host unreachable"));
    }

    SECTION("unreachable-proto") {
        fake_controller.request(IP_PERIPHERAL,
            satcat5::ip::ICMP_UNREACHABLE_PROTO);
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("Destination protocol unreachable"));
    }

    SECTION("unreachable-port") {
        fake_controller.request(IP_PERIPHERAL,
            satcat5::ip::ICMP_UNREACHABLE_PORT);
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("Destination port unreachable"));
    }

    SECTION("time-exceeded") {
        fake_controller.request(IP_PERIPHERAL,
            satcat5::ip::ICMP_FRAG_TIMEOUT);
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("Time exceeded"));
    }

    SECTION("ttl-expired") {
        fake_controller.request(IP_PERIPHERAL,
            satcat5::ip::ICMP_TTL_EXPIRED);
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("TTL expired"));
    }

    SECTION("bad-header") {
        fake_controller.request(IP_PERIPHERAL,
            satcat5::ip::ICMP_IP_HDR_OPTION);
        log.disable();
        satcat5::poll::service_all();
        CHECK(log.contains("IP header error"));
    }
}
