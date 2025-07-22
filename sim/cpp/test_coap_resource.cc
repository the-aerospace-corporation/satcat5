//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
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
#include <satcat5/io_cbor.h>
#include <satcat5/utils.h>

using satcat5::coap::Resource;
using satcat5::coap::ResourceEcho;
using satcat5::coap::ResourceLog;
using satcat5::coap::ResourceNull;
using satcat5::coap::ResourceServer;
using satcat5::udp::PORT_COAP;
namespace coap = satcat5::coap;

TEST_CASE("coap_resource") {
    SATCAT5_TEST_START;

    // Check that Resource matching logic works correctly
    SECTION("matching") {
        CHECK(ResourceNull("aaa") == ResourceNull("aaa"));
        CHECK(ResourceNull("aaa") != ResourceNull("aab"));
        CHECK(ResourceNull("aaa") != ResourceNull("aaaa"));
        CHECK(ResourceNull("aaa") != ResourceNull(""));

        const size_t uri_path_len = SATCAT5_COAP_MAX_URI_PATH_LEN;
        std::string max_len(uri_path_len, 'a');
        std::string oversized(uri_path_len+1, 'a');

        // Test max length, 1x oversized, and both oversized
        CHECK(ResourceNull(max_len.c_str()) ==
              ResourceNull(max_len.c_str()));
        CHECK(ResourceNull(max_len.c_str()) !=
              ResourceNull(oversized.c_str()));
        CHECK(ResourceNull(oversized.c_str()) !=
              ResourceNull(max_len.c_str()));
        CHECK(ResourceNull(oversized.c_str()) !=
              ResourceNull(oversized.c_str()));
    }
}

TEST_CASE("coap_resource_server") {
    // Simulation infrastructure
    SATCAT5_TEST_START;
    satcat5::test::CrosslinkIp xlink(__FILE__);

    // Client and server setup
    satcat5::coap::SimpleClientUdp client(&xlink.net0.m_udp);
    ResourceServer server(&xlink.net1.m_udp);
    server.bind(PORT_COAP);
    ResourceNull test1  (&server, "test1");
    ResourceNull nested (&server, "test1/test2/03");
    ResourceNull root   (&server, "");

    // Open a connection + wait for ARP resolution
    REQUIRE(client.connect(xlink.IP1, PORT_COAP));
    xlink.timer.sim_wait(1000);

    // Check we can find a Resource
    SECTION("resource_match") {
        // GET /test1, POST /test1, PUT /test1, DELETE /test1
        auto method = GENERATE(
            coap::CODE_GET, coap::CODE_POST, coap::CODE_PUT, coap::CODE_DELETE);
        CHECK(client.request(method, "test1"));
        xlink.timer.sim_wait(100);

        // Check resource exists: all should return 4.05 Method Not Allowed
        coap::ReadSimple r1(client.response_all());
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_BAD_METHOD);
        CHECK(r1.msg_id() == client.msg_id());
        CHECK(r1.token() == client.msg_id());
    }

    // Check we can find a nested resource
    SECTION("resource_nested") {
        // GET /test1/test2/03
        CHECK(client.request(coap::CODE_GET, "test1/test2/03"));
        xlink.timer.sim_wait(100);

        // Check resource exists: 4.05 Method Not Allowed
        coap::ReadSimple r1(client.response_all());
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_BAD_METHOD);
        CHECK(r1.msg_id() == client.msg_id());
        CHECK(r1.token() == client.msg_id());
    }

    // Check we can register a root resource
    SECTION("resource_root") {
        // GET / with implicit Uri-Path
        CHECK(client.request(coap::CODE_GET, nullptr));
        xlink.timer.sim_wait(100);

        // Check resource exists: 4.05 Method Not Allowed
        coap::ReadSimple r1(client.response_all());
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_BAD_METHOD);
        CHECK(r1.msg_id() == client.msg_id());
        CHECK(r1.token() == client.msg_id());
        r1.read_finalize();

        // GET / with explicit Uri-Path
        CHECK(client.request(coap::CODE_GET, ""));
        xlink.timer.sim_wait(100);

        // Check resource exists: 4.05 Method Not Allowed
        coap::ReadSimple r2(client.response_all());
        CHECK(r2.type() == coap::TYPE_ACK);
        CHECK(r2.code() == coap::CODE_BAD_METHOD);
        CHECK(r2.msg_id() == client.msg_id());
        CHECK(r2.token() == client.msg_id());
        r2.read_finalize();
    }

    // Check that a response is given when the Resource does not exist
    SECTION("resource_not_found") {
        // GET /test2
        CHECK(client.request(coap::CODE_GET, "test2"));
        xlink.timer.sim_wait(100);

        // Check resource does not exist: 4.04 Not Found
        coap::ReadSimple r1(client.response_all());
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_NOT_FOUND);
        CHECK(r1.msg_id() == client.msg_id());
        CHECK(r1.token() == client.msg_id());
        r1.read_finalize();
    }

    // Check that a request that isn't GET, POST, PUT, or DELETE is rejected
    SECTION("resource_bad_method") {
        // Bad request code to resource /test1
        CHECK(client.request(coap::CODE_SERVER_ERROR, "test1"));
        xlink.timer.sim_wait(100);

        // Check request is rejected: 4.05 Method Not Allowed
        coap::ReadSimple r1(client.response_all());
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_BAD_METHOD);
        CHECK(r1.msg_id() == client.msg_id());
        CHECK(r1.token() == client.msg_id());
        r1.read_finalize();
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
    satcat5::coap::SimpleClientUdp client(&xlink.net0.m_udp);
    ResourceServer server(&xlink.net1.m_udp);
    server.bind(PORT_COAP);
    ResourceEcho echo(&server, "echo");
    ResourceLog log_d(&server, "log/d", satcat5::log::DEBUG);
    ResourceLog log_i(&server, "log/i", satcat5::log::INFO);
    ResourceLog log_w(&server, "log/w", satcat5::log::WARNING);
    ResourceLog log_e(&server, "log/e", satcat5::log::ERROR);
    ResourceLog log_c(&server, "log/c", satcat5::log::CRITICAL);

    // Open a connection + wait for ARP resolution
    coap::Connection* c1 = nullptr;
    REQUIRE((c1 = client.connect(xlink.IP1, PORT_COAP)));
    xlink.timer.sim_wait(1000);
    u16 msg_id = 123;

    // Check the Echo resource works as expected
    SECTION("resource_echo") {
        // GET /echo "Example Payload"
        const std::string example_payload = "Example Payload";
        coap::Writer w1(c1->open_request());
        REQUIRE(w1.ready());
        w1.write_header(coap::TYPE_CON, coap::CODE_GET, msg_id, msg_id);
        w1.write_option(coap::OPTION_URI_PATH, "echo");
        w1.write_option(coap::OPTION_FORMAT, coap::FORMAT_TEXT);
        satcat5::io::Writeable* dst = nullptr;
        REQUIRE((dst = w1.write_data()));
        dst->write_str(example_payload.c_str());
        CHECK(w1.write_finalize());
        xlink.timer.sim_wait(100);
        ++msg_id;

        // Check response is echoed back with 2.05 Content
        coap::ReadSimple r1(client.response_all());
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_CONTENT);
        CHECK(satcat5::test::read(r1.read_data(), example_payload));
        r1.read_finalize();

        // GET /echo with CBOR data.
        satcat5::cbor::MapWriterStatic<> cwr;
        cwr.add_bool("key1", true);
        cwr.add_item("key2", u32(1234));
        CHECK(client.request(coap::CODE_GET, "echo", cwr));
        xlink.timer.sim_wait(100);

        // Check response is echoed back with CBOR data.
        satcat5::cbor::MapReaderStatic<> crd(client.response_data());
        CHECK(crd.get_bool("key1").value());
        CHECK(crd.get_uint("key2").value() == 1234);

        // Check other accessors.
        CHECK(echo.ip()  == server.ip());
        CHECK(echo.udp() == server.udp());
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
        CHECK(client.request(coap::CODE_POST, "log/d", debug_entry.c_str()));
        xlink.timer.sim_wait(100);

        // Check response is added to the log with 2.01 Created
        coap::ReadSimple r1(client.response_all());
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_CREATED);
        CHECK(r1.read_data()->get_read_ready() == 0); // Empty response
        r1.read_finalize();
        check_log_buff(&log_buff, satcat5::log::DEBUG, "log/d: " + debug_entry);
    }

    SECTION("resource_log_errors") {
        // POST /log/d with Content-Type CBOR, should be rejected
        coap::Writer w1(c1->open_request());
        REQUIRE(w1.ready());
        w1.write_header(coap::TYPE_CON, coap::CODE_POST, msg_id, msg_id);
        w1.write_option(coap::OPTION_URI_PATH, "log");
        w1.write_option(coap::OPTION_URI_PATH, "d");
        w1.write_option(coap::OPTION_FORMAT, coap::FORMAT_CBOR);
        satcat5::io::Writeable* dst = nullptr;
        REQUIRE((dst = w1.write_data()));
        dst->write_str("Bad Format");
        CHECK(w1.write_finalize());
        xlink.timer.sim_wait(100);
        coap::ReadSimple r1(client.response_all());
        CHECK(r1.type() == coap::TYPE_ACK);
        CHECK(r1.code() == coap::CODE_BAD_FORMAT);
        r1.read_finalize();
        ++msg_id;

        // POST /log/d with an empty payload, should be rejected
        coap::Writer w2(c1->open_request());
        REQUIRE(w2.ready());
        w2.write_header(coap::TYPE_CON, coap::CODE_POST, msg_id, msg_id);
        w2.write_option(coap::OPTION_URI_PATH, "log");
        w2.write_option(coap::OPTION_URI_PATH, "d");
        w2.write_option(coap::OPTION_FORMAT, coap::FORMAT_TEXT);
        CHECK(w2.write_finalize());
        xlink.timer.sim_wait(100);
        coap::ReadSimple r2(client.response_all());
        CHECK(r2.type() == coap::TYPE_ACK);
        CHECK(r2.code() == coap::CODE_BAD_REQUEST);
        r2.read_finalize();
        ++msg_id;
    }
}
