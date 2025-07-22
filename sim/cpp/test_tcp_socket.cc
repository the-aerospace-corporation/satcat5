//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for OS-provided TCP socket

#include <hal_posix/tcp_socket.h>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>

TEST_CASE("TCP-socket-posix") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;

    // Units under test.
    satcat5::tcp::SocketPosix client, server;

    // Basic back-and-forth test using plaintext hostname.
    SECTION("hostname") {
        // Connect using "localhost" as the hostname.
        REQUIRE(server.bind(1234));
        REQUIRE(client.connect("localhost", 1234));
        timer.sim_wait(100);
        CHECK(server.ready());
        CHECK(client.ready());
        // Send some data in each direction.
        CHECK(satcat5::test::write(&client, "Client to server test message."));
        CHECK(satcat5::test::write(&server, "Server to client test message."));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&client, "Server to client test message."));
        CHECK(satcat5::test::read(&server, "Client to server test message."));
    }

    // Basic back-and-forth test using hard-coded IP address.
    SECTION("ip_addr") {
        // Connect using a hard-coded IP address.
        satcat5::ip::Addr localhost(127, 0, 0, 1);
        REQUIRE(server.bind(1234));
        REQUIRE(client.connect(localhost, 1234));
        timer.sim_wait(100);
        CHECK(server.ready());
        CHECK(client.ready());
        // Send some data in each direction.
        CHECK(satcat5::test::write(&client, "Client to server test message."));
        CHECK(satcat5::test::write(&server, "Server to client test message."));
        timer.sim_wait(100);
        CHECK(satcat5::test::read(&client, "Server to client test message."));
        CHECK(satcat5::test::read(&server, "Client to server test message."));
    }

    // Test the rate-limiter: 4096 bytes @ 128 kbps = 256 msec.
    SECTION("rate_limit") {
        // Connect using a hard-coded IP address.
        satcat5::ip::Addr localhost(127, 0, 0, 1);
        REQUIRE(server.bind(1234));
        REQUIRE(client.connect(localhost, 1234));
        timer.sim_wait(100);
        CHECK(server.ready());
        CHECK(client.ready());
        // Set rate limit, then send some data in each direction.
        client.set_rate_kbps(128);
        CHECK(satcat5::test::write_random_final(&client, 4096));
        CHECK(satcat5::test::write_random_final(&server, 4096));
        timer.sim_wait(100);
        CHECK(client.get_read_ready() < 3000);
        CHECK(server.get_read_ready() < 3000);
        timer.sim_wait(100);
        CHECK(client.get_read_ready() < 4000);
        CHECK(server.get_read_ready() < 4000);
        timer.sim_wait(100);
        CHECK(client.get_read_ready() == 4096);
        CHECK(server.get_read_ready() == 4096);
    }
}
