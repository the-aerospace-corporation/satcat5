//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test the Ethernet dispatcher

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/eth_socket.h>

using satcat5::net::Type;
namespace eth = satcat5::eth;

class MockProtocol : public eth::Protocol {
public:
    MockProtocol(eth::Dispatch* dispatch, u16 etype)
        : Protocol(dispatch, {etype}), m_rcvd(0) {}
    MockProtocol(eth::Dispatch* dispatch, u16 etype, u16 vtag)
        : Protocol(dispatch, {etype}, {vtag}), m_rcvd(0) {}
    virtual ~MockProtocol() {}

    u32 m_rcvd;

protected:
    void frame_rcvd(satcat5::io::LimitedRead& src) override {
        m_rcvd = src.read_u32();
    }
};

Type make_type(u8 x) {return Type(x);}

// Send a packet with a short message.
void send_msg(satcat5::io::Writeable* wr, u16 vtag, u16 etype, u32 msg) {
    wr->write_obj(eth::MACADDR_BROADCAST);
    wr->write_obj(eth::MACADDR_BROADCAST);
    if (vtag) {
        wr->write_u16(0x8100);
        wr->write_u16(vtag);
    }
    wr->write_u16(etype);
    wr->write_u32(msg);
    wr->write_finalize();
}

TEST_CASE("ethernet-dispatch") {
    // Unit under test, plus I/O buffers.
    satcat5::io::PacketBufferHeap tx, rx;
    const eth::MacAddr MAC_LOCAL = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11};
    eth::Dispatch uut(MAC_LOCAL, &tx, &rx);

    // Register a few mock protocol handlers.
    MockProtocol p1(&uut, 12);
    MockProtocol p2(&uut, 34);

    SECTION("bound") {
        CHECK(uut.bound(make_type(12)));
        CHECK(uut.bound(make_type(34)));
        CHECK_FALSE(uut.bound(make_type(56)));
    }

    SECTION("register") {
        // Register and unregister handlers in psuedorandom order.
        MockProtocol* p3 = new MockProtocol(&uut, 56);
        MockProtocol* p4 = new MockProtocol(&uut, 78);
        MockProtocol* p5 = new MockProtocol(&uut, 90, 1234);
        delete p4;
        delete p3;
        delete p5;
    }

    SECTION("overflow-min") {
        // Fill transmit buffer with min-length packets until it is full.
        // Confirm "open_write" returns zero before "write_finalize" fails.
        while(1) {
            auto wr = uut.open_write(eth::MACADDR_BROADCAST, {4242});
            if (wr) {REQUIRE(wr->write_finalize());} else break;
        }
    }

    SECTION("proto-rx") {
        // Send some data to each MockProtocol.
        CHECK(p1.m_rcvd == 0);
        CHECK(p2.m_rcvd == 0);
        send_msg(&rx, 0, 12, 0x1234);
        send_msg(&rx, 0, 34, 0x3456);
        satcat5::poll::service_all();
        CHECK(p1.m_rcvd == 0x1234);
        CHECK(p2.m_rcvd == 0x3456);
    }

    SECTION("socket-rx") {
        // Bind a socket object to EtherType 34.
        eth::Socket sock(&uut);
        sock.bind({34});
        // Send some data to that port.
        send_msg(&rx, 0, 34, 0xBEEF);
        satcat5::poll::service_all();
        CHECK(sock.read_u32() == 0xBEEF);
    }

    SECTION("bind-by-vlan") {
        // Bind two socket objects to the same EtherType on different VLANs.
        eth::Socket sock1(&uut);
        sock1.bind({42}, {1});  // VID = 1
        eth::Socket sock2(&uut);
        sock2.bind({42}, {2});  // VID = 2
        eth::Socket sock3(&uut);
        sock3.bind({42});       // Any other VID
        // Send some data to each socket.
        send_msg(&rx, 1, 42, 0xDEAD);
        send_msg(&rx, 2, 42, 0xBEEF);
        send_msg(&rx, 3, 42, 0x1234);
        satcat5::poll::service_all();
        CHECK(sock1.read_u32() == 0xDEAD);
        CHECK(sock2.read_u32() == 0xBEEF);
        CHECK(sock3.read_u32() == 0x1234);
    }

    SECTION("write-vlan") {
        // Direct write with boosted priority.
        satcat5::io::Writeable* wr = uut.open_write(
            eth::MACADDR_BROADCAST, eth::ETYPE_IPV4, eth::VTAG_PRIORITY7);
        REQUIRE(wr);
        wr->write_u16(0xABCD);
        wr->write_u32(0x87654321);
        CHECK(wr->write_finalize());
        // Check raw bytes written to buffer.
        CHECK(tx.read_u32() == 0xFFFFFFFFu);    // Dst and Src addresses
        CHECK(tx.read_u32() == 0xFFFFDEADu);
        CHECK(tx.read_u32() == 0xBEEF1111u);
        CHECK(tx.read_u32() == 0x8100E000u);    // VLAN tag
        CHECK(tx.read_u32() == 0x0800ABCDu);    // EtherType + data
        CHECK(tx.read_u32() == 0x87654321u);
    }
}
