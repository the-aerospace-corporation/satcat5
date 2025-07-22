//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the "coap::Connection" and "coap::Endpoint" classes.

#include <hal_posix/coap_posix.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/coap_client.h>
#include <satcat5/coap_connection.h>
#include <satcat5/coap_endpoint.h>
#include <satcat5/coap_reader.h>
#include <satcat5/coap_writer.h>
#include <vector>

using satcat5::coap::Connection;
using satcat5::coap::ConnectionUdp;
using satcat5::coap::EndpointSppFwd;
using satcat5::coap::Reader;
using satcat5::udp::PORT_COAP;
using satcat5::util::prng;
namespace coap = satcat5::coap;

// Buffer holding a single CoAP message.
// (Used to test handling of duplicate and out-of-order messages.)
struct TestMessage {
    satcat5::io::ArrayWriteStatic<SATCAT5_COAP_BUFFSIZE> msg;

    // Construct an empty buffer, or clone an existing one.
    TestMessage() {}
    TestMessage(const TestMessage& other) {
        msg.write_bytes(other.msg.written_len(), other.msg.buffer());
        msg.write_finalize();
    }

    // Transmit this buffer through the connection's test API.
    bool inject(Connection* obj) const {
        return obj && obj->test_inject(msg.written_len(), msg.buffer());
    }

    // Write a new message to this buffer.
    satcat5::io::Writeable* open() {
        msg.write_abort();
        return &msg;
    }

    // Write this buffer to another destination
    bool send_to(satcat5::io::Writeable* dst) const {
        CHECK(msg.written_len() > 0);   // Sanity check / fail-loud
        if (dst) dst->write_bytes(msg.written_len(), msg.buffer());
        return dst && dst->write_finalize();
    }
};

// Select different reply modes for TestEndpoint:
enum class Reply {
    NONE,           // No response (default)
    ECHO_NOW,       // Echo immediately
    ECHO_SEP,       // Echo w/ separated response
    ECHO_RAND,      // Echo w/ random response mode
    RESET,          // Always reply with reset
};

// Templated implementation of the coap::Endpoint class.
// (Allows test logic to be reused in SPP or UDP mode.)
template <typename Parent>
class TestEndpoint : public Parent {
public:
    // Internal state:
    TestMessage last_sent;
    Reply       mode;
    u16         msgid;
    u64         token;
    unsigned    count_req;
    unsigned    count_ack;
    unsigned    count_err;

    // Template constructor sets reply mode, then forwards all
    // remaining arguments to the parent's constructor.
    template <typename... Args>
    TestEndpoint(Reply reply, Args... args)
        : Parent(args...)
        , mode(reply)
        , msgid(prng.next())
        , token(0)
        , count_req(0)
        , count_ack(0)
        , count_err(0)
    {
        // Nothing else to initialize.
    }

    // Helper function for sending simple messages.
    // (Note: This does not update the "last_sent" buffer.)
    bool send_ping(Connection* obj) {
        return obj->ping(++msgid);
    }

    // Send a request through the designated connection object.
    bool send_request(Connection* obj, u8 type, coap::Code code, unsigned len) {
        coap::Writer request(last_sent.open());
        token = prng.next();
        request.write_header(type, code, ++msgid, token);
        if (len) satcat5::test::write_random_bytes(request.write_data(), len);
        return request.write_finalize()
            && last_sent.send_to(obj->open_request());
    }

    // Event callbacks for incoming CoAP messages.
    void coap_request(Connection* obj, Reader* msg) override {
        ++count_req;        // Update stats.

        // Response type?
        if (mode == Reply::ECHO_NOW) {
            // Normal piggybacked response
            CHECK(send_echo(obj, msg));
        } else if (mode == Reply::ECHO_SEP) {
            // Multipart separate response
            CHECK(obj->open_separate(msg));
            CHECK(send_echo(obj, msg));
        } else if (mode == Reply::ECHO_RAND) {
            // Randomly choose piggybacked or separated mode
            if (prng.next() & 1) obj->open_separate(msg);
            CHECK(send_echo(obj, msg));
        } else if (mode == Reply::RESET) {
            // Simulate a severe error
            CHECK(send_reset(obj, msg));
        }
    }

    void coap_error(Connection* obj) override {
        ++count_err;
    }

    void coap_response(Connection* obj, Reader* msg) override {
        ++count_ack;
    }

    void coap_ping(const Reader* msg) override {
        ++count_ack;
    }

private:
    bool send_echo(Connection* obj, Reader* msg) {
        // Write the message to the test buffer.
        coap::Writer reply(last_sent.open());
        reply.write_header(coap::CODE_VALID, obj);
        // Echo received message contents.
        auto rd = msg->read_data();
        auto wr = reply.write_data();
        bool ok = rd && wr && rd->copy_and_finalize(wr);
        // If successful, send a copy to the unit under test.
        return ok && last_sent.send_to(obj->open_response_auto());
    }

    bool send_reset(Connection* obj, Reader* msg) {
        // Write the message to the test buffer.
        coap::Writer reply(last_sent.open());
        reply.write_header(
            coap::TYPE_RST, coap::CODE_UNAVAILABLE,
            msg->msg_id(), msg->token(), msg->tkl());
        bool ok = reply.write_finalize();
        // If successful, send a copy to the unit under test.
        return ok && last_sent.send_to(obj->open_response_auto());
    }
};

// Shortcut for TestEndpoint with a CCSDS-SPP connection.
typedef TestEndpoint<satcat5::coap::EndpointSpp> TestEndpointSpp;

// Shortcut for TestEndpoint with an array of UDP connections.
template <unsigned SIZE> using TestEndpointUdp
    = TestEndpoint<satcat5::coap::EndpointUdpStatic<SIZE> >;

static constexpr u16 APID_COAP = 123;

TEST_CASE("coap_endpoint_spp") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::CrosslinkSpp xlink(__FILE__);

    // Basic echo test with a single request and acknowledgement.
    SECTION("basic") {
        // Client and server setup.
        TestEndpointSpp client(Reply::NONE,     &xlink.spp0, APID_COAP);
        TestEndpointSpp server(Reply::ECHO_NOW, &xlink.spp1, APID_COAP);
        Connection *c1 = client.connection();
        // Test the proxy token accessors.
        c1->set_proxy_token(1234);
        CHECK(c1->get_proxy_token() == 1234);
        // Send a few confirmable CoAP requests.
        constexpr unsigned COUNT = 10;
        for (unsigned a = 1 ; a <= COUNT ; ++a) {
            CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
            xlink.timer.sim_wait(1000);
            CHECK(server.count_req == a);
            CHECK(client.count_ack == a);
            CHECK(server.count_err == 0);
            CHECK(client.count_err == 0);
        }
        // Send a non-confirmable CoAP request.
        CHECK(client.send_request(c1, coap::TYPE_NON, coap::CODE_GET, 32));
        xlink.timer.sim_wait(1000);
        CHECK(server.count_req == COUNT+1);
        CHECK(client.count_ack == COUNT+1);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
    }

    // Basic echo test, but with randomized packet loss.
    // (Each transaction should still be completed exactly once.)
    SECTION("lossy") {
        // Client and server setup.
        TestEndpointSpp client(Reply::NONE,     &xlink.spp0, APID_COAP);
        TestEndpointSpp server(Reply::ECHO_NOW, &xlink.spp1, APID_COAP);
        Connection *c1 = client.connection();
        // Repeat the test several times at a fixed loss rate.
        xlink.set_loss_rate(0.20f);
        for (unsigned a = 1 ; a <= 20 ; ++a) {
            // Send a single confirmable CoAP request.
            CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
            xlink.timer.sim_wait(10000);
            CHECK(server.count_req == a);
            CHECK(client.count_ack == a);
            CHECK(server.count_err == 0);
            CHECK(client.count_err == 0);
        }
    }

    // Test the "Coap ping" request/response.
    SECTION("ping") {
        // Client and server setup.
        TestEndpointSpp client(Reply::NONE,     &xlink.spp0, APID_COAP);
        TestEndpointSpp server(Reply::ECHO_NOW, &xlink.spp1, APID_COAP);
        Connection *c1 = client.connection();
        // Send a single ping request.
        CHECK(client.send_ping(c1));
        xlink.timer.sim_wait(1000);
        CHECK(server.count_req == 0);
        CHECK(client.count_ack == 1);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
    }

    // Test response without request.
    SECTION("request_missing") {
        // Client and server setup.
        TestEndpointSpp client(Reply::NONE,     &xlink.spp0, APID_COAP);
        TestEndpointSpp server(Reply::ECHO_NOW, &xlink.spp1, APID_COAP);
        Connection *c1 = client.connection();
        // Send a confirmable CoAP request, but reset the client
        // connection before the response is received.
        CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
        c1->close();
        xlink.timer.sim_wait(1000);
        // The server's "unexpected" response should trigger a reset.
        CHECK(server.count_req == 1);
        CHECK(client.count_ack == 0);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
    }

    // Test the case where user logic fails to issue a response.
    SECTION("response_missing") {
        // Client and server setup.
        TestEndpointSpp client(Reply::NONE,     &xlink.spp0, APID_COAP);
        TestEndpointSpp server(Reply::NONE,     &xlink.spp1, APID_COAP);
        Connection *c1 = client.connection();
        // Send a confirmable CoAP request, then retry to exhaustion.
        CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
        xlink.timer.sim_wait(30000);
        // Both client and server should eventually timeout.
        CHECK(server.count_req == 1);
        CHECK(client.count_ack == 0);
        CHECK(server.count_err == 1);
        CHECK(client.count_err == 1);
    }

    // Test response to a reset message.
    SECTION("reset") {
        // Client and server setup.
        TestEndpointSpp client(Reply::NONE,     &xlink.spp0, APID_COAP);
        TestEndpointSpp server(Reply::RESET,    &xlink.spp1, APID_COAP);
        Connection *c1 = client.connection();
        // Send a single confirmable CoAP request.
        CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
        xlink.timer.sim_wait(1000);
        CHECK(server.count_req == 1);
        CHECK(client.count_ack == 0);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 1);
    }

    // Basic test of a separated response.
    SECTION("separated") {
        // Client and server setup.
        TestEndpointSpp client(Reply::NONE,     &xlink.spp0, APID_COAP);
        TestEndpointSpp server(Reply::ECHO_SEP, &xlink.spp1, APID_COAP);
        Connection *c1 = client.connection();
        // Send a single confirmable CoAP request.
        CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
        xlink.timer.sim_wait(1000);
        CHECK(server.count_req == 1);
        CHECK(client.count_ack == 1);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
    }

    // Test separated response with randomized packet loss.
    SECTION("separated_lossy") {
        // Client and server setup.
        TestEndpointSpp client(Reply::NONE,     &xlink.spp0, APID_COAP);
        TestEndpointSpp server(Reply::ECHO_SEP, &xlink.spp1, APID_COAP);
        Connection *c1 = client.connection();
        // Repeat the test several times at a fixed loss rate.
        xlink.set_loss_rate(0.20f);
        for (unsigned a = 1 ; a <= 20 ; ++a) {
            // Send a single confirmable CoAP request.
            CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
            xlink.timer.sim_wait(10000);
            CHECK(server.count_req == a);
            CHECK(client.count_ack == a);
            CHECK(server.count_err == 0);
            CHECK(client.count_err == 0);
        }
    }

    // Test the SimpleClientSPP class.
    SECTION("simple_client") {
        // Client and server setup.
        satcat5::coap::SimpleClientSpp client(&xlink.spp0, APID_COAP);
        TestEndpointSpp server(Reply::ECHO_NOW, &xlink.spp1, APID_COAP);
        // Send a single ping request.
        CHECK(client.request(coap::CODE_GET, "ping", "TestMsg"));
        xlink.timer.sim_wait(1000);
        CHECK(satcat5::test::read(client.response_data(), "TestMsg"));
    }
}

TEST_CASE("coap_endpoint_udp") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::CrosslinkIp xlink(__FILE__);

    // Basic echo test with a single request and acknowledgement.
    SECTION("basic") {
        // Client and server setup.
        TestEndpointUdp<1> client(Reply::NONE,     &xlink.net0.m_udp);
        TestEndpointUdp<1> server(Reply::ECHO_NOW, &xlink.net1.m_udp);
        server.bind(PORT_COAP);
        // Open connection, without waiting for ARP resolution.
        Connection *c1 = 0;
        REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
        ConnectionUdp *c2 = (ConnectionUdp*)c1;
        REQUIRE(c2->is_match_addr(xlink.IP1, PORT_COAP));
        // Send a few confirmable CoAP requests.
        constexpr unsigned COUNT = 10;
        for (unsigned a = 1 ; a <= COUNT ; ++a) {
            CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
            xlink.timer.sim_wait(1000);
            CHECK(server.count_req == a);
            CHECK(client.count_ack == a);
            CHECK(server.count_err == 0);
            CHECK(client.count_err == 0);
        }
        // Send a non-confirmable CoAP request.
        CHECK(client.send_request(c1, coap::TYPE_NON, coap::CODE_GET, 32));
        xlink.timer.sim_wait(1000);
        CHECK(server.count_req == COUNT+1);
        CHECK(client.count_ack == COUNT+1);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
    }

    // Basic echo test, but with randomized packet loss.
    // (Each transaction should still be completed exactly once.)
    SECTION("lossy") {
        // Repeat the test several times at a fixed loss rate.
        xlink.set_loss_rate(0.20f);
        for (unsigned a = 0 ; a < 20 ; ++a) {
            // Flush ARP cache before each run.
            xlink.net0.m_route.route_flush();
            // Client and server setup.
            TestEndpointUdp<1> client(Reply::NONE,     &xlink.net0.m_udp);
            TestEndpointUdp<1> server(Reply::ECHO_NOW, &xlink.net1.m_udp);
            server.bind(PORT_COAP);
            // Open connection + wait for ARP resolution.
            Connection *c1 = 0;
            REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
            xlink.timer.sim_wait(10000);
            // Send a single confirmable CoAP request.
            CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
            xlink.timer.sim_wait(10000);
            CHECK(server.count_req == 1);
            CHECK(client.count_ack == 1);
            CHECK(server.count_err == 0);
            CHECK(client.count_err == 0);
        }
    }

    // Echo test with multiple concurrent clients.
    SECTION("concurrent") {
        log.suppress("All connections busy.");
        // Client and server setup.
        TestEndpointUdp<3> client(Reply::NONE,     &xlink.net0.m_udp);
        TestEndpointUdp<2> server(Reply::ECHO_NOW, &xlink.net1.m_udp);
        server.bind(PORT_COAP);
        // Open each test connection from the client.
        Connection *c1 = 0, *c2 = 0, *c3 = 0;
        REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
        xlink.timer.sim_wait(100);  // ARP resolution + cache
        REQUIRE((c2 = client.connect(xlink.IP1, PORT_COAP)));
        REQUIRE((c3 = client.connect(xlink.IP1, PORT_COAP)));
        // A fourth connection attempt should overflow.
        CHECK_FALSE(client.connect(xlink.IP1, PORT_COAP));
        // Send two confirmable requests.
        CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
        CHECK(client.send_request(c2, coap::TYPE_CON, coap::CODE_GET, 32));
        // Both requests should succeed.
        xlink.timer.sim_wait(1000);
        CHECK(server.count_req == 2);
        CHECK(client.count_ack == 2);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
        // A third request should initially fail, then succeed on
        // a later retransmission once the cache slots unlock.
        // (In FAST config, cached request timeout is 12.0 seconds.)
        xlink.timer.sim_wait(8000);
        CHECK(client.send_request(c3, coap::TYPE_CON, coap::CODE_GET, 32));
        xlink.timer.sim_wait(8000);
        // Third connection should (eventually) reuse an old cache slot.
        CHECK(server.count_req == 3);
        CHECK(client.count_ack == 3);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
    }

    // Echo test send to a multicast address.
    SECTION("multicast") {
        // Client and server setup.
        TestEndpointUdp<1> client(Reply::NONE,     &xlink.net0.m_udp);
        TestEndpointUdp<1> server(Reply::ECHO_NOW, &xlink.net1.m_udp);
        server.bind(PORT_COAP);
        // Open the "All COAP nodes" address (Section 12.8).
        Connection *c1 = 0;
        REQUIRE((c1 = client.connect(satcat5::udp::MULTICAST_COAP, PORT_COAP)));
        // Send a single non-confirmable CoAP request.
        // (Server should wait from 1-1000 msec before replying.)
        CHECK(client.send_request(c1, coap::TYPE_NON, coap::CODE_GET, 32));
        xlink.timer.sim_wait(1);
        CHECK(client.connections(0).is_request());
        CHECK(server.connections(0).is_response());
        xlink.timer.sim_wait(2000);
        CHECK(server.count_req == 1);
        CHECK(client.count_ack == 1);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
    }

    // Test the "Coap ping" request/response.
    SECTION("ping") {
        // Client and server setup.
        TestEndpointUdp<1> client(Reply::NONE,     &xlink.net0.m_udp);
        TestEndpointUdp<1> server(Reply::ECHO_NOW, &xlink.net1.m_udp);
        server.bind(PORT_COAP);
        // Open connection + wait for ARP resolution.
        Connection *c1 = 0;
        REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
        xlink.timer.sim_wait(1000);
        // Send a single ping request.
        CHECK(client.send_ping(c1));
        xlink.timer.sim_wait(1000);
        CHECK(server.count_req == 0);
        CHECK(client.count_ack == 1);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
    }

    // Test response to a reset message.
    SECTION("reset") {
        // Client and server setup.
        TestEndpointUdp<1> client(Reply::NONE,     &xlink.net0.m_udp);
        TestEndpointUdp<1> server(Reply::RESET,    &xlink.net1.m_udp);
        server.bind(PORT_COAP);
        // Open connection and send, without waiting for ARP resolution.
        Connection *c1 = 0;
        REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
        CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
        xlink.timer.sim_wait(1000);
        CHECK(server.count_req == 1);
        CHECK(client.count_ack == 0);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 1);
    }

    // Basic test of a separated response.
    SECTION("separated") {
        // Client and server setup.
        TestEndpointUdp<1> client(Reply::NONE,     &xlink.net0.m_udp);
        TestEndpointUdp<1> server(Reply::ECHO_SEP, &xlink.net1.m_udp);
        server.bind(PORT_COAP);
        // Open connection + wait for ARP resolution.
        Connection *c1 = 0;
        REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
        xlink.timer.sim_wait(1000);
        // Send a single confirmable CoAP request.
        CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
        xlink.timer.sim_wait(1000);
        CHECK(server.count_req == 1);
        CHECK(client.count_ack == 1);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
    }

    // Test separated response with randomized packet loss.
    SECTION("separated_lossy") {
        // Repeat the test several times at a fixed loss rate.
        xlink.set_loss_rate(0.20f);
        for (unsigned a = 0 ; a < 20 ; ++a) {
            // Flush ARP cache before each run.
            xlink.net0.m_route.route_flush();
            // Client and server setup.
            TestEndpointUdp<1> client(Reply::NONE,     &xlink.net0.m_udp);
            TestEndpointUdp<1> server(Reply::ECHO_SEP, &xlink.net1.m_udp);
            server.bind(PORT_COAP);
            // Open connection + wait for ARP resolution.
            Connection *c1 = 0;
            REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
            xlink.timer.sim_wait(10000);
            // Send a single confirmable CoAP request.
            CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
            xlink.timer.sim_wait(10000);
            CHECK(server.count_req == 1);
            CHECK(client.count_ack == 1);
            CHECK(server.count_err == 0);
            CHECK(client.count_err == 0);
        }
    }

    // Test a mixture of piggybacked and separated responses.
    SECTION("separated_random") {
        // Repeat the test several times at a fixed loss rate.
        xlink.set_loss_rate(0.20f);
        for (unsigned a = 0 ; a < 20 ; ++a) {
            // Flush ARP cache before each run.
            xlink.net0.m_route.route_flush();
            // Client and server setup.
            TestEndpointUdp<1> client(Reply::NONE,      &xlink.net0.m_udp);
            TestEndpointUdp<1> server(Reply::ECHO_RAND, &xlink.net1.m_udp);
            server.bind(PORT_COAP);
            // Open connection + wait for ARP resolution.
            Connection *c1 = 0;
            REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
            xlink.timer.sim_wait(10000);
            // Send a single confirmable CoAP request.
            CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
            xlink.timer.sim_wait(10000);
            CHECK(server.count_req == 1);
            CHECK(client.count_ack == 1);
            CHECK(server.count_err == 0);
            CHECK(client.count_err == 0);
        }
    }

    // Test retransmission of a cached response.
    SECTION("stale") {
        // Client and server setup.
        TestEndpointUdp<1> client(Reply::NONE,     &xlink.net0.m_udp);
        TestEndpointUdp<1> server(Reply::ECHO_NOW, &xlink.net1.m_udp);
        server.bind(PORT_COAP);
        // Open connection + wait for ARP resolution.
        Connection *c1 = 0;
        REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
        xlink.timer.sim_wait(1000);
        // Send two single confirmable CoAP requests, noting the
        // outgoing message contents so we can duplicate them later.
        CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
        TestMessage request1(client.last_sent);
        xlink.timer.sim_wait(1000);
        CHECK(client.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
        TestMessage request2(client.last_sent);
        xlink.timer.sim_wait(1000);
        CHECK(server.count_req == 2);
        CHECK(client.count_ack == 2);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
        // Inject duplicates of each request. Server should retransmit
        // from cache, and client should discard unexpected responses.
        CHECK(request1.inject(c1));
        xlink.timer.sim_wait(1000);
        CHECK(request2.inject(c1));
        xlink.timer.sim_wait(1000);
        // The duplicates should not generate new events.
        CHECK(server.count_req == 2);
        CHECK(client.count_ack == 2);
        CHECK(server.count_err == 0);
        CHECK(client.count_err == 0);
    }

    // Test the SimpleClientUdp class.
    SECTION("simple_client") {
        // Client and server setup.
        satcat5::coap::SimpleClientUdp client(&xlink.net0.m_udp);
        TestEndpointUdp<1> server(Reply::ECHO_NOW, &xlink.net1.m_udp);
        server.bind(PORT_COAP);
        // Open connection + wait for ARP resolution.
        CHECK(client.connect(xlink.IP1, PORT_COAP));
        xlink.timer.sim_wait(1000);
        // Send three ping requests, and read each queued response.
        CHECK(client.request(coap::CODE_GET, "ping", "TestMsg1"));
        xlink.timer.sim_wait(1000);
        CHECK(client.request(coap::CODE_GET, "ping", "TestMsg2"));
        xlink.timer.sim_wait(1000);
        CHECK(client.request(coap::CODE_GET, "ping", "TestMsg3"));
        xlink.timer.sim_wait(1000);
        CHECK(satcat5::test::read(client.response_data(), "TestMsg1"));
        CHECK(satcat5::test::read(client.response_data(), "TestMsg2"));
        CHECK(client.response_discard());           // Discard TestMsg3
        CHECK_FALSE(client.response_discard());     // No more responses
    }
}

TEST_CASE("coap_endpoint_multi") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::CrosslinkSpp xlink_spp(__FILE__);
    satcat5::test::CrosslinkIp  xlink_udp(__FILE__);

    // Client and server setup, including the "EndpointSppFwd" bridge.
    TestEndpointUdp<1> client_udp(Reply::ECHO_NOW, &xlink_udp.net0.m_udp);
    TestEndpointUdp<1> server_udp(Reply::ECHO_NOW, &xlink_udp.net1.m_udp);
    server_udp.bind(PORT_COAP);
    TestEndpointSpp client_spp(Reply::ECHO_NOW, &xlink_spp.spp0, APID_COAP);
    EndpointSppFwd  server_spp(&xlink_spp.spp1, APID_COAP, &server_udp);

    // Open UDP connection + wait for ARP resolution.
    Connection *c1 = client_spp.connection();
    Connection *c2 = client_udp.connect(xlink_udp.IP1, PORT_COAP);
    Connection *c3 = server_spp.connection();
    xlink_udp.timer.sim_wait(1000);

    // Basic echo test over each interface.
    SECTION("echo") {
        // Send a few confirmable CoAP requests.
        constexpr unsigned COUNT = 10;
        for (unsigned a = 1 ; a <= COUNT ; ++a) {
            CHECK(client_spp.send_request(c1, coap::TYPE_CON, coap::CODE_GET, 32));
            xlink_udp.timer.sim_wait(1000);
            CHECK(client_udp.send_request(c2, coap::TYPE_CON, coap::CODE_GET, 32));
            xlink_udp.timer.sim_wait(1000);
            CHECK(server_udp.count_req == 2*a);
            CHECK(client_udp.count_ack == a);
            CHECK(client_spp.count_ack == a);
            CHECK(server_udp.count_err == 0);
            CHECK(client_udp.count_err == 0);
            CHECK(client_spp.count_err == 0);
        }
    }

    // Reversed-direction echo test.
    SECTION("echo_rev") {
        // Send a few confirmable CoAP requests.
        constexpr unsigned COUNT = 10;
        for (unsigned a = 1 ; a <= COUNT ; ++a) {
            CHECK(server_udp.send_request(c3, coap::TYPE_CON, coap::CODE_GET, 32));
            xlink_udp.timer.sim_wait(1000);
            CHECK(server_udp.count_ack == a);
            CHECK(client_spp.count_req == a);
            CHECK(server_udp.count_err == 0);
            CHECK(client_udp.count_err == 0);
            CHECK(client_spp.count_err == 0);
        }
    }

    // Test a "Coap ping" over each interface.
    SECTION("ping") {
        // Send a single ping request over each interface.
        CHECK(client_spp.send_ping(c1));
        xlink_udp.timer.sim_wait(1000);
        CHECK(client_udp.send_ping(c2));
        xlink_udp.timer.sim_wait(1000);
        CHECK(server_udp.send_ping(c3));
        xlink_udp.timer.sim_wait(1000);
        CHECK(server_udp.count_ack == 1);
        CHECK(client_udp.count_ack == 1);
        CHECK(client_spp.count_ack == 1);
        CHECK(server_udp.count_err == 0);
        CHECK(client_udp.count_err == 0);
        CHECK(client_spp.count_err == 0);
    }

    // Test error-forwarding through the SPP server.
    SECTION("reset") {
        client_spp.mode = Reply::RESET;
        // Send a request from the joint server to the SPP client.
        CHECK(server_udp.send_request(c3, coap::TYPE_CON, coap::CODE_GET, 32));
        // The client should respond with a RESET message.
        xlink_udp.timer.sim_wait(1000);
        CHECK(server_udp.count_err == 1);
        CHECK(client_udp.count_err == 0);
        CHECK(client_spp.count_err == 0);
    }
}
