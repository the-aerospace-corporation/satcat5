//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the "coap::Resource" and "coap::ResourceServer" classes.

#include <string>
#include <hal_posix/coap_posix.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/coap_reader.h>
#include <satcat5/coap_resource.h>
#include <satcat5/coap_writer.h>
#include <satcat5/utils.h>

using satcat5::coap::Resource;
using satcat5::coap::ResourceEcho;
using satcat5::coap::ResourceLog;
using satcat5::coap::ResourceServer;
using satcat5::udp::PORT_COAP;
namespace coap = satcat5::coap;

TEST_CASE("coap_resource") {
    SATCAT5_TEST_START;

    // Check that Resource matching logic works correctly
    SECTION("matching") {
        CHECK(Resource("aaa") == Resource("aaa"));
        CHECK(Resource("aaa") != Resource("aab"));
        CHECK(Resource("aaa") != Resource("aaaa"));
        CHECK(Resource("aaa") != Resource(""));
        const size_t uri_path_len = SATCAT5_COAP_MAX_URI_PATH_LEN;
        std::string max_len(uri_path_len, 'a');
        std::string oversized(uri_path_len+1, 'a');

        // Test max length, 1x oversized, and both oversized
        CHECK(Resource(max_len.c_str()) ==
                Resource(std::string(max_len).c_str()));
        CHECK(Resource(max_len.c_str()) !=
                Resource(std::string(oversized).c_str()));
        CHECK(Resource(oversized.c_str()) !=
                Resource(std::string(max_len).c_str()));
        CHECK(Resource(oversized.c_str()) !=
                Resource(std::string(oversized).c_str()));
    }
}

// Test endpoint for making requests and handling responses
class TestEndpoint : public coap::EndpointUdpHeap {
public:
    // Constructor
    TestEndpoint(satcat5::udp::Dispatch* udp, unsigned size)
        : coap::EndpointUdpHeap(udp, size) {}

    // Saves the incoming message to `last_msg`, dropping unknown options
    void coap_request(coap::Connection* obj, coap::Reader& msg) override {}
    void coap_response(coap::Connection* obj, coap::Reader& msg) override {
        last_msg.write_abort();
        coap::Writer wr(&last_msg);
        wr.write_header(msg.type(), msg.code(), msg);
        if (msg.uri_path()) {
            wr.write_option(satcat5::coap::OPTION_URI_PATH,
                msg.uri_path().value());
        }
        if (msg.format()) {
            wr.write_option(satcat5::coap::OPTION_FORMAT, msg.format().value());
        }
        if (msg.size1()) {
            wr.write_option(satcat5::coap::OPTION_SIZE1, msg.size1().value());
        }
        msg.read_data()->copy_to(wr.write_data());
        wr.write_finalize();
    }

    // Create a reader for the last message
    satcat5::io::ArrayRead read_last_buf()
        { return { last_msg.written_len(), last_msg.buffer() }; }

protected:
    satcat5::io::ArrayWriteStatic<SATCAT5_COAP_BUFFSIZE> last_msg;
};

TEST_CASE("coap_resource_server") {

    // Simulation infrastructure
    SATCAT5_TEST_START;
    satcat5::test::CrosslinkIp xlink(__FILE__);

    // Client and server setup
    TestEndpoint client(&xlink.net0.m_udp, 1);
    ResourceServer server(&xlink.net1.m_udp);
    server.bind(PORT_COAP);
    Resource test1("test1");
    server.add_resource(&test1);
    Resource nested("test1/test2/03");
    server.add_resource(&nested);
    Resource root("");
    server.add_resource(&root);

    // Open a connection + wait for ARP resolution
    coap::Connection* c1 = nullptr;
    REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
    xlink.timer.sim_wait(1000);

    // Check we can find a Resource
    SECTION("resource_match") {

        // GET /test1, POST /test1, PUT /test1, DELETE /test1
        auto method = GENERATE(coap::CODE_GET, coap::CODE_POST, coap::CODE_PUT,
            coap::CODE_DELETE);
        unsigned msg_id = 0;
        coap::Writer w1(c1->open_request());
        REQUIRE(w1.ready());
        w1.write_header(coap::TYPE_CON, method, msg_id, msg_id);
        w1.write_option(coap::OPTION_URI_PATH, "test1");
        CHECK(w1.write_finalize());
        xlink.timer.sim_wait(100);

        // Check resource exists: all should return 4.05 Method Not Allowed
        satcat5::io::ArrayRead resp1 = client.read_last_buf();
        coap::Reader r1(&resp1);
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_BAD_METHOD);
        CHECK(r1.msg_id() == msg_id);
        CHECK(r1.token() == msg_id);
        msg_id++;
    }

    // Check we can find a nested resource
    SECTION("resource_nested") {

        // GET /test1/test2/03
        coap::Writer w1(c1->open_request());
        REQUIRE(w1.ready());
        w1.write_header(coap::TYPE_CON, coap::CODE_GET, 0, 0);
        w1.write_option(coap::OPTION_URI_PATH, "test1");
        w1.write_option(coap::OPTION_URI_PATH, "test2");
        w1.write_option(coap::OPTION_URI_PATH, "03");
        CHECK(w1.write_finalize());
        xlink.timer.sim_wait(100);

        // Check resource exists: 4.05 Method Not Allowed
        satcat5::io::ArrayRead resp1 = client.read_last_buf();
        coap::Reader r1(&resp1);
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_BAD_METHOD);
        CHECK(r1.msg_id() == 0);
        CHECK(r1.token() == 0);
    }

    // Check we can register a root resource
    SECTION("resource_root") {

        // GET / with implicit Uri-Path
        coap::Writer w1(c1->open_request());
        REQUIRE(w1.ready());
        w1.write_header(coap::TYPE_CON, coap::CODE_GET, 0, 0);
        // No Uri-Path
        CHECK(w1.write_finalize());
        xlink.timer.sim_wait(100);
        satcat5::io::ArrayRead resp1 = client.read_last_buf();
        coap::Reader r1(&resp1);
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_BAD_METHOD);
        CHECK(r1.msg_id() == 0);
        CHECK(r1.token() == 0);

        // GET / with explicit Uri-Path
        coap::Writer w2(c1->open_request());
        REQUIRE(w2.ready());
        w2.write_header(coap::TYPE_CON, coap::CODE_GET, 1, 1);
        w2.write_option(coap::OPTION_URI_PATH, "");
        CHECK(w2.write_finalize());
        xlink.timer.sim_wait(100);
        satcat5::io::ArrayRead resp2 = client.read_last_buf();
        coap::Reader r2(&resp2);
        CHECK(r2.type() == coap::TYPE_ACK);
        CHECK(r2.code() == coap::CODE_BAD_METHOD);
        CHECK(r2.msg_id() == 1);
        CHECK(r2.token() == 1);
    }

    // Check that a response is given when the Resource does not exist
    SECTION("resource_not_found") {

        // GET /test2
        coap::Writer w1(c1->open_request());
        REQUIRE(w1.ready());
        w1.write_header(coap::TYPE_CON, coap::CODE_GET, 0, 0);
        w1.write_option(coap::OPTION_URI_PATH, "test2");
        CHECK(w1.write_finalize());
        xlink.timer.sim_wait(100);

        // Check resource does not exist: 4.04 Not Found
        satcat5::io::ArrayRead resp1 = client.read_last_buf();
        coap::Reader r1(&resp1);
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_NOT_FOUND);
        CHECK(r1.msg_id() == 0);
        CHECK(r1.token() == 0);
    }

    // Check that a request that isn't GET, POST, PUT, or DELETE is rejected
    SECTION("resource_bad_method") {

        // Bad request code to resource /test1
        coap::Writer w1(c1->open_request());
        REQUIRE(w1.ready());
        w1.write_header(coap::TYPE_CON, coap::CODE_SERVER_ERROR, 0, 0);
        w1.write_option(coap::OPTION_URI_PATH, "test1");
        CHECK(w1.write_finalize());
        xlink.timer.sim_wait(100);

        // Check request is rejected: 4.05 Method Not Allowed
        satcat5::io::ArrayRead resp1 = client.read_last_buf();
        coap::Reader r1(&resp1);
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_BAD_METHOD);
        CHECK(r1.msg_id() == 0);
        CHECK(r1.token() == 0);
    }
}

// Helper function for checking LogToWriteable messages.
void check_log_buff(satcat5::io::Readable* src, s8 priority, std::string ref) {
    // Discard everything up to the delimiter character.
    // (LogToWriteable adds an emoji prefix followed by TAB.)
    u8 DELIM = (u8)'\t';
    while ((src->get_read_ready() > 0) && (src->read_u8() != DELIM)) {}

    // Read everything after that point and strip newline (CR+LF).
    std::string msg = satcat5::io::read_str(src);
    REQUIRE(msg.size() > 2);
    std::string trim = std::string(msg.begin(), msg.end()-2);

    // The remainder should exactly match the reference string.
    // Check priority?
    CHECK(trim == ref);
}

TEST_CASE("coap_resource_implementation") {

    // Simulation infrastructure
    SATCAT5_TEST_START;
    satcat5::test::CrosslinkIp xlink(__FILE__);
    satcat5::io::ArrayWriteStatic<SATCAT5_COAP_BUFFSIZE> msg_buff;

    // Client and server setup
    TestEndpoint client(&xlink.net0.m_udp, 1);
    ResourceServer server(&xlink.net1.m_udp);
    server.bind(PORT_COAP);
    ResourceEcho echo("echo");
    server.add_resource(&echo);
    ResourceLog log_d("log/d", satcat5::log::DEBUG);
    ResourceLog log_i("log/i", satcat5::log::INFO);
    ResourceLog log_w("log/w", satcat5::log::WARNING);
    ResourceLog log_e("log/e", satcat5::log::ERROR);
    ResourceLog log_c("log/c", satcat5::log::CRITICAL);
    server.add_resource(&log_d);
    server.add_resource(&log_i);
    server.add_resource(&log_w);
    server.add_resource(&log_e);
    server.add_resource(&log_c);

    // Open a connection + wait for ARP resolution
    coap::Connection* c1 = nullptr;
    REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
    xlink.timer.sim_wait(1000);

    // Check the Echo resource works as expected
    SECTION("resource_echo") {

        // GET /echo "Example Payload"
        const std::string example_payload = "Example Payload";
        coap::Writer w1(c1->open_request());
        REQUIRE(w1.ready());
        w1.write_header(coap::TYPE_CON, coap::CODE_GET, 0, 0);
        w1.write_option(coap::OPTION_URI_PATH, "echo");
        satcat5::io::Writeable* dst = nullptr;
        REQUIRE((dst = w1.write_data()));
        dst->write_str(example_payload.c_str());
        CHECK(w1.write_finalize());
        xlink.timer.sim_wait(100);

        // Check response is echoed back with 2.05 Content
        satcat5::io::ArrayRead resp1 = client.read_last_buf();
        coap::Reader r1(&resp1);
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_CONTENT);
        CHECK(satcat5::test::read(r1.read_data(), example_payload));
    }

    // Check the Log resource works as expected
    SECTION("resource_log") {

        // Disable console logging and add a log buffer for testing
        log.disable(); // Suppress console logging
        satcat5::io::PacketBufferHeap log_buff;
        satcat5::log::ToWriteable log_test(&log_buff);
        log_buff.read_finalize();

        // POST /log/d "Debug Log Entry"
        const std::string debug_entry = "Debug Log Entry";
        coap::Writer w1(c1->open_request());
        REQUIRE(w1.ready());
        w1.write_header(coap::TYPE_CON, coap::CODE_POST, 0, 0);
        w1.write_option(coap::OPTION_URI_PATH, "log");
        w1.write_option(coap::OPTION_URI_PATH, "d");
        satcat5::io::Writeable* dst = nullptr;
        REQUIRE((dst = w1.write_data()));
        dst->write_str(debug_entry.c_str()); // Null termination not copied!
        CHECK(w1.write_finalize());
        xlink.timer.sim_wait(100);

        // Check response is added to the log with 2.01 Created
        satcat5::io::ArrayRead resp1 = client.read_last_buf();
        coap::Reader r1(&resp1);
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_CREATED);
        CHECK(r1.read_data()->get_read_ready() == 0); // Empty response
        check_log_buff(&log_buff, satcat5::log::DEBUG, "log/d: " + debug_entry);

        // Reset console logging
        log.m_threshold = satcat5::log::DEBUG;
    }

    SECTION("resource_log_errors") {

        // POST /log/d with Content-Type CBOR, should be rejected
        coap::Writer w1(c1->open_request());
        REQUIRE(w1.ready());
        w1.write_header(coap::TYPE_CON, coap::CODE_POST, 0, 0);
        w1.write_option(coap::OPTION_URI_PATH, "log");
        w1.write_option(coap::OPTION_URI_PATH, "d");
        w1.write_option(coap::OPTION_FORMAT, coap::FORMAT_CBOR);
        satcat5::io::Writeable* dst = nullptr;
        REQUIRE((dst = w1.write_data()));
        dst->write_str("Bad Format");
        CHECK(w1.write_finalize());
        xlink.timer.sim_wait(100);
        satcat5::io::ArrayRead resp1 = client.read_last_buf();
        coap::Reader r1(&resp1);
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_BAD_FORMAT);

        // POST /log/d with an empty payload, should be rejected
        coap::Writer w2(c1->open_request());
        REQUIRE(w2.ready());
        w2.write_header(coap::TYPE_CON, coap::CODE_POST, 1, 1);
        w2.write_option(coap::OPTION_URI_PATH, "log");
        w2.write_option(coap::OPTION_URI_PATH, "d");
        w2.write_option(coap::OPTION_FORMAT, coap::FORMAT_TEXT);
        CHECK(w2.write_finalize());
        xlink.timer.sim_wait(100);
        satcat5::io::ArrayRead resp2 = client.read_last_buf();
        coap::Reader r2(&resp2);
        CHECK(r2.type() == coap::TYPE_ACK);
        CHECK(r2.code() == coap::CODE_BAD_REQUEST);
    }
}
