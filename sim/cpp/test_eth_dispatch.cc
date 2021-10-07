//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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
    virtual ~MockProtocol() {}

    u32 m_rcvd;

protected:
    void frame_rcvd(satcat5::io::LimitedRead& src) override {
        m_rcvd = src.read_u32();
    }
};

Type make_type(u8 x) {return Type(x);}

// Send a packet with a short message.
void send_msg(satcat5::io::Writeable* wr, u16 etype, u32 msg) {
    wr->write_obj(eth::MACADDR_BROADCAST);
    wr->write_obj(eth::MACADDR_BROADCAST);
    wr->write_u16(etype);
    wr->write_u32(msg);
    wr->write_finalize();
}

TEST_CASE("ethernet-dispatch") {
    // Unit under test, plus I/O buffers.
    satcat5::io::PacketBufferHeap tx, rx;
    eth::Dispatch uut(eth::MACADDR_BROADCAST, &tx, &rx);

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
        MockProtocol* p5 = new MockProtocol(&uut, 90);
        delete p4;
        delete p3;
        delete p5;
    }

    SECTION("proto-rx") {
        // Send some data to each MockProtocol.
        CHECK(p1.m_rcvd == 0);
        CHECK(p2.m_rcvd == 0);
        send_msg(&rx, 12, 0x1234);
        send_msg(&rx, 34, 0x3456);
        satcat5::poll::service_all();
        CHECK(p1.m_rcvd == 0x1234);
        CHECK(p2.m_rcvd == 0x3456);
    }

    SECTION("socket-rx") {
        // Bind a socket object to EtherType 34.
        eth::Socket sock(&uut);
        sock.bind({34});
        // Send some data to that port.
        send_msg(&rx, 34, 0xBEEF);
        satcat5::poll::service_all();
        CHECK(sock.read_u32() == 0xBEEF);
    }
}
