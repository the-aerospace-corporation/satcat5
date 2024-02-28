//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Unit test for the Echo protocol (Raw-Ethernet and UDP variants)
//

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/eth_socket.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/net_echo.h>
#include <satcat5/udp_dispatch.h>
#include <satcat5/udp_socket.h>

TEST_CASE("net-echo") {
    satcat5::log::ToConsole log;
    satcat5::util::PosixTimer timer;

    // Network communication infrastructure.
    const satcat5::eth::MacAddr MAC_SERVER = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11};
    const satcat5::eth::MacAddr MAC_CLIENT = {0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22};
    const satcat5::ip::Addr IP_SERVER = {192, 168, 11, 11};
    const satcat5::ip::Addr IP_CLIENT = {192, 168, 12, 12};
    satcat5::io::PacketBufferHeap c2s, s2c;
    satcat5::eth::Dispatch eth_server(MAC_SERVER, &s2c, &c2s);
    satcat5::eth::Dispatch eth_client(MAC_CLIENT, &c2s, &s2c);
    satcat5::ip::Dispatch ip_server(IP_SERVER, &eth_server, &timer);
    satcat5::ip::Dispatch ip_client(IP_CLIENT, &eth_client, &timer);
    satcat5::udp::Dispatch udp_server(&ip_server);
    satcat5::udp::Dispatch udp_client(&ip_client);

    // Test configuration constants.
    const satcat5::eth::MacType ETYPE_REQ = {0x1234};
    const satcat5::eth::MacType ETYPE_ACK = {0x2345};

    SECTION("eth") {
        // Create server and client.
        satcat5::eth::ProtoEcho uut(&eth_server, ETYPE_REQ, ETYPE_ACK);
        satcat5::eth::Socket sock(&eth_client);

        // Open connection.
        CHECK_FALSE(sock.ready_tx());
        CHECK_FALSE(sock.ready_rx());
        sock.connect(MAC_SERVER, ETYPE_REQ, ETYPE_ACK);
        CHECK(sock.ready_tx());
        CHECK(sock.ready_rx());

        // Send a request and check reply.
        sock.write_u32(0xCAFED00D);
        CHECK(sock.write_finalize());
        satcat5::poll::service_all();
        CHECK(sock.read_u32() == 0xCAFED00D);

        // Cleanup.
        sock.close();
    }

    SECTION("udp") {
        // Configure server and client.
        satcat5::udp::ProtoEcho uut(&udp_server);
        satcat5::udp::Socket sock(&udp_client);
        sock.connect(IP_SERVER, satcat5::udp::PORT_ECHO);

        // Send a request and check reply.
        sock.write_u32(0xCAFED00D);
        sock.write_finalize();
        satcat5::poll::service_all();
        CHECK(sock.read_u32() == 0xCAFED00D);

        // Cleanup.
        sock.close();
    }
}
