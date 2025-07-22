//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for UDP dispatch and related blocks

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/net_tpipe.h>

using satcat5::io::CopyMode;

static const unsigned TEST_ITER = 10;
static const unsigned TEST_SIZE = 4321;

TEST_CASE("Eth-Tpipe") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Network communication infrastructure.
    satcat5::test::CrosslinkIp xlink(__FILE__);
    const satcat5::eth::MacAddr MAC_SERVER(xlink.MAC0);
    const satcat5::eth::MacAddr MAC_CLIENT(xlink.MAC1);
    const satcat5::eth::MacType ETYPE_SERVER = {12345};
    const satcat5::eth::MacType ETYPE_WRONG  = {12346};

    // Units under test.
    satcat5::eth::Tpipe uut_server(&xlink.net0.m_eth);
    satcat5::eth::Tpipe uut_client(&xlink.net1.m_eth);
    uut_server.bind(ETYPE_SERVER);

    // Set retransmit and timeout parameters for this test.
    uut_client.set_retransmit(500);
    uut_client.set_timeout(30000);
    uut_server.set_retransmit(500);
    uut_server.set_timeout(30000);

    // Basic bidirectional messaging.
    SECTION("basic") {
        uut_client.connect(MAC_SERVER, ETYPE_SERVER);
        // First back-and-forth exchange.
        CHECK(satcat5::test::write(&uut_client, "Message from client to server."));
        CHECK(satcat5::test::write(&uut_server, "Message from server to client."));
        xlink.timer.sim_wait(2000);
        CHECK(satcat5::test::read(&uut_client, "Message from server to client."));
        CHECK(satcat5::test::read(&uut_server, "Message from client to server."));
        // Another back-and-forth exchange.
        CHECK(satcat5::test::write(&uut_client, "Lorem ipsum dolor sit amet."));
        CHECK_FALSE(uut_client.completed());
        xlink.timer.sim_wait(2000);
        CHECK(satcat5::test::write(&uut_server, "Test message plz ignore."));
        CHECK_FALSE(uut_server.completed());
        xlink.timer.sim_wait(2000);
        CHECK(satcat5::test::read(&uut_client, "Test message plz ignore."));
        CHECK(satcat5::test::read(&uut_server, "Lorem ipsum dolor sit amet."));
        CHECK(uut_client.completed());
        CHECK(uut_server.completed());
        // Close the connection.
        uut_client.close();
        xlink.timer.sim_wait(2000);
    }

    // Longer test with randomized packet loss.
    SECTION("lossy") {
        // Connect extra-large source and sink buffers.
        // (The working buffers are too small to do this in one step.)
        satcat5::io::StreamBufferHeap src(2*TEST_SIZE), sink(2*TEST_SIZE);
        satcat5::io::BufferedCopy cpy_src(&src, &uut_client, CopyMode::STREAM);
        satcat5::io::BufferedCopy cpy_dst(&uut_server, &sink, CopyMode::STREAM);
        // Repeat the test a few times...
        xlink.set_loss_rate(0.2f);
        for (unsigned a = 0 ; a < TEST_ITER ; ++a) {
            // Write a few kilobytes of random data to the source buffer.
            satcat5::test::RandomSource ref(TEST_SIZE);
            REQUIRE(ref.read()->copy_and_finalize(&src));
            satcat5::poll::service_all();
            // Connect and execute the data transfer.
            uut_client.connect(MAC_SERVER, ETYPE_SERVER);
            xlink.timer.sim_wait(60000);
            // Confirm data was received successfully.
            CHECK(uut_client.completed());
            CHECK(satcat5::test::read_equal(ref.read(), &sink));
            // Cleanup before the next attempt.
            uut_client.close();
            uut_server.close();
            xlink.timer.sim_wait(1000);
        }
    }

    // Intentionally cause a connection timeout.
    SECTION("timeout") {
        uut_client.connect(MAC_SERVER, ETYPE_WRONG);
        CHECK(satcat5::test::write(&uut_client, "Retry sending several times..."));
        xlink.timer.sim_wait(45000);    // Default timeout = 30 seconds.
        CHECK_FALSE(uut_client.completed());
    }

    // Test the transmit-only mode.
    SECTION("txonly") {
        // Set 100% packet-loss rate on server-to-client packets.
        xlink.eth0.set_loss_rate(1.0);
        uut_client.connect(MAC_SERVER, ETYPE_SERVER);
        uut_client.set_txonly();
        // Connect extra-large source and sink buffers.
        satcat5::io::StreamBufferHeap src(TEST_SIZE), sink(TEST_SIZE);
        satcat5::io::BufferedCopy cpy_src(&src, &uut_client, CopyMode::STREAM);
        satcat5::io::BufferedCopy cpy_dst(&uut_server, &sink, CopyMode::STREAM);
        // Generate and transfer a block of psuedorandom data.
        satcat5::test::RandomSource ref(TEST_SIZE);
        REQUIRE(ref.read()->copy_and_finalize(&src));
        xlink.timer.sim_wait(60000);
        // Confirm successful transfer.
        CHECK(uut_client.completed());
        CHECK(satcat5::test::read_equal(ref.read(), &sink));
    }
}

TEST_CASE("Udp-Tpipe") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Network communication infrastructure.
    satcat5::test::CrosslinkIp xlink(__FILE__);
    const satcat5::udp::Addr IP_SERVER(xlink.IP0);
    const satcat5::udp::Addr IP_CLIENT(xlink.IP1);
    const satcat5::udp::Port PORT_SERVER = {12345};
    const satcat5::udp::Port PORT_WRONG  = {12346};

    // Units under test.
    satcat5::udp::Tpipe uut_server(&xlink.net0.m_udp);
    satcat5::udp::Tpipe uut_client(&xlink.net1.m_udp);
    uut_server.bind(PORT_SERVER);

    // Set retransmit and timeout parameters for this test.
    uut_client.set_retransmit(500);
    uut_client.set_timeout(30000);
    uut_server.set_retransmit(500);
    uut_server.set_timeout(30000);

    // Basic bidirectional messaging.
    SECTION("basic") {
        uut_client.connect(IP_SERVER, PORT_SERVER);
        // First back-and-forth exchange.
        CHECK(satcat5::test::write(&uut_client, "Message from client to server."));
        CHECK(satcat5::test::write(&uut_server, "Message from server to client."));
        xlink.timer.sim_wait(2000);
        CHECK(satcat5::test::read(&uut_client, "Message from server to client."));
        CHECK(satcat5::test::read(&uut_server, "Message from client to server."));
        // Another back-and-forth exchange.
        CHECK(satcat5::test::write(&uut_client, "Lorem ipsum dolor sit amet."));
        CHECK_FALSE(uut_client.completed());
        xlink.timer.sim_wait(2000);
        CHECK(satcat5::test::write(&uut_server, "Test message plz ignore."));
        CHECK_FALSE(uut_server.completed());
        xlink.timer.sim_wait(2000);
        CHECK(satcat5::test::read(&uut_client, "Test message plz ignore."));
        CHECK(satcat5::test::read(&uut_server, "Lorem ipsum dolor sit amet."));
        CHECK(uut_client.completed());
        CHECK(uut_server.completed());
        // Close the connection.
        uut_client.close();
        xlink.timer.sim_wait(2000);
    }

    // Longer test with randomized packet loss.
    SECTION("lossy") {
        // Connect extra-large source and sink buffers.
        // (The working buffers are too small to do this in one step.)
        satcat5::io::StreamBufferHeap src(2*TEST_SIZE), sink(2*TEST_SIZE);
        satcat5::io::BufferedCopy cpy_src(&src, &uut_client, CopyMode::STREAM);
        satcat5::io::BufferedCopy cpy_dst(&uut_server, &sink, CopyMode::STREAM);
        // Repeat the test a few times...
        xlink.set_loss_rate(0.2f);
        for (unsigned a = 0 ; a < TEST_ITER ; ++a) {
            // Write a few kilobytes of random data to the source buffer.
            satcat5::test::RandomSource ref(TEST_SIZE);
            REQUIRE(ref.read()->copy_and_finalize(&src));
            satcat5::poll::service_all();
            // Connect and execute the data transfer.
            uut_client.connect(IP_SERVER, PORT_SERVER);
            xlink.timer.sim_wait(60000);
            // Confirm data was received successfully.
            CHECK(uut_client.completed());
            CHECK(satcat5::test::read_equal(ref.read(), &sink));
            // Cleanup before the next attempt.
            uut_client.close();
            uut_server.close();
            xlink.timer.sim_wait(1000);
        }
    }

    // Intentionally cause a connection timeout.
    SECTION("timeout") {
        log.suppress("Destination port unreachable");
        uut_client.connect(IP_SERVER, PORT_WRONG);
        CHECK(satcat5::test::write(&uut_client, "Retry sending several times..."));
        xlink.timer.sim_wait(45000);    // Default timeout = 30 seconds.
        CHECK_FALSE(uut_client.completed());
    }
}
