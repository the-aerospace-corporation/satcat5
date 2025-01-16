//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the "coap::Reader" and "coap::Writer" classes.

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/coap_reader.h>
#include <satcat5/coap_writer.h>

using satcat5::io::ArrayRead;

// CoAP captures provided by Daniel Mangum
// https://github.com/hasheddan/coap-pcap
// (These are the CoAP message contents after DTLS decryption.)
static const u8 EXAMPLE_QUERY[] = {
    0x44, 0x02, 0xa8, 0x94, 0x7d, 0x5b, 0x82, 0x5d,
    0xb4, 0x6c, 0x6f, 0x67, 0x73, 0x11, 0x32, 0xff,
    0x7b, 0x22, 0x6c, 0x65, 0x76, 0x65, 0x6c, 0x22,
    0x3a, 0x22, 0x69, 0x6e, 0x66, 0x6f, 0x22, 0x2c,
    0x22, 0x6d, 0x6f, 0x64, 0x75, 0x6c, 0x65, 0x22,
    0x3a, 0x22, 0x67, 0x6f, 0x6c, 0x69, 0x6f, 0x74,
    0x68, 0x5f, 0x62, 0x61, 0x73, 0x69, 0x63, 0x73,
    0x22, 0x2c, 0x22, 0x6d, 0x73, 0x67, 0x22, 0x3a,
    0x22, 0x57, 0x61, 0x69, 0x74, 0x69, 0x6e, 0x67,
    0x20, 0x66, 0x6f, 0x72, 0x20, 0x63, 0x6f, 0x6e,
    0x6e, 0x65, 0x63, 0x74, 0x69, 0x6f, 0x6e, 0x20,
    0x74, 0x6f, 0x20, 0x47, 0x6f, 0x6c, 0x69, 0x6f,
    0x74, 0x68, 0x2e, 0x2e, 0x2e, 0x22, 0x7d};
static const u8 EXAMPLE_RESPONSE[] = {
    0x64, 0x43, 0xa8, 0x94, 0x7d, 0x5b, 0x82, 0x5d,
    0x48, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xca,
    0x0c, 0x80, 0xff, 0x4f, 0x4b};
static const char* EXAMPLE_JSON =
    "{\"level\":\"info\",\"module\":\"golioth_basics\"," \
    "\"msg\":\"Waiting for connection to Golioth...\"}";

// Constructed examples to reach specific edge cases.
static const u8 EXAMPLE_LONG[] = {
    0x64, 0x43, 0xa8, 0x94, 0x7d, 0x5b, 0x82, 0x5d,
    0xdd, 0x00, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55,     // Option #1
    0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd,
    0xe5, 0x12, 0x34, 0x11, 0x22, 0x33, 0x44, 0x55,     // Option #2
    0x1e, 0x12, 0x34, 0x11, 0x22, 0x33, 0x44, 0x55};    // Option #3
static const u8 EXAMPLE_BAD_HDR[] = {
    0x69, 0x43, 0xa8, 0x94, 0x7d, 0x5b, 0x82, 0x5d};    // TKL = 9
static const u8 EXAMPLE_BAD_ID[] = {
    0x64, 0x43, 0xa8, 0x94, 0x7d, 0x5b, 0x82, 0x5d,
    0xf0, 0xff, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55};    // Invalid option ID
static const u8 EXAMPLE_EMPTY_VALID[] = {
    0x40, 0x00, 0xa8, 0x94};                            // Code = empty, TKL = 0
static const u8 EXAMPLE_EMPTY_TOKEN[] = {
    0x44, 0x00, 0xa8, 0x94, 0x7d, 0x5b, 0x82, 0x5d};    // Code = empty, TKL = 4
static const u8 EXAMPLE_NO_DATA[] = {
    0x64, 0x43, 0xa8, 0x94, 0x7d, 0x5b, 0x82, 0x5d};    // No options or data
static const u8 EXAMPLE_UNKNOWN_CRIT[] {
    0x64, 0x43, 0xa8, 0x94, 0x7d, 0x5b, 0x82, 0x5d,
    0xd0, 0xf4};                                        // Option #1 (ID = 257)
static const u8 EXAMPLE_SIZE1[] = {
    0x64, 0x43, 0xa8, 0x94, 0x7d, 0x5b, 0x82, 0x5d,
    0xd2, 0x2f, 0x05, 0xDC};                            // Option #1

class TestReader : public satcat5::coap::Reader
{
public:
    satcat5::io::PacketBufferHeap m_options;
    explicit TestReader(satcat5::io::Readable* src) : Reader(src) {}
protected:
    // Extra options saved as (u16 id, u16 len, data...)
    void read_user_option() override {
        m_options.write_abort();
        m_options.write_u16(m_opt.id());
        m_options.write_u16(m_opt.len());
        m_opt.copy_to(&m_options);
        m_options.write_finalize();
    }
};

TEST_CASE("coap_reader") {
    SATCAT5_TEST_START;

    // Read each field in the example query.
    SECTION("read_query") {
        // Start reading the message header.
        ArrayRead msg(EXAMPLE_QUERY, sizeof(EXAMPLE_QUERY));
        TestReader uut(&msg);
        // Check all basic header fields.
        CHECK_FALSE(uut.error());
        CHECK(uut.version()     == satcat5::coap::VERSION1);
        CHECK(uut.type()        == satcat5::coap::TYPE_CON);
        CHECK(uut.tkl()         == 4);
        CHECK(uut.code()        == satcat5::coap::CODE_POST);
        CHECK(uut.msg_id()      == 0xA894);
        CHECK(uut.token()       == 0x7D5B825D);
        // Options: URI-Path = "logs", Content-Format = "application/json"
        uut.read_options();
        CHECK_FALSE(uut.error());
        CHECK(uut.uri_path());
        CHECK(strcmp(uut.uri_path().value(), "logs") == 0);
        CHECK(uut.format());
        CHECK(uut.format().value() == satcat5::coap::FORMAT_JSON);
        CHECK_FALSE(uut.size1());
        CHECK(uut.m_options.get_read_ready() == 0);
        // Check the message data.
        CHECK(satcat5::test::read(uut.read_data(), EXAMPLE_JSON));
    }

    // Read each field in the example response.
    SECTION("read_response") {
        // Start reading the message header.
        ArrayRead msg(EXAMPLE_RESPONSE, sizeof(EXAMPLE_RESPONSE));
        TestReader uut(&msg);
        // Check all basic header fields.
        CHECK_FALSE(uut.error());
        CHECK(uut.version()     == satcat5::coap::VERSION1);
        CHECK(uut.type()        == satcat5::coap::TYPE_ACK);
        CHECK(uut.tkl()         == 4);
        CHECK(uut.code()        == satcat5::coap::CODE_VALID);
        CHECK(uut.msg_id()      == 0xA894);
        CHECK(uut.token()       == 0x7D5B825D);
        // Options: Etag = 0x000000000000CA0C, Content-Format = "text/plain"
        uut.read_options();
        CHECK_FALSE(uut.error());
        CHECK(uut.format());
        CHECK(uut.format().value()      == satcat5::coap::FORMAT_TEXT);
        CHECK_FALSE(uut.size1());
        REQUIRE(uut.m_options.get_read_ready() > 0);
        CHECK(uut.m_options.read_u16()  == satcat5::coap::OPTION_ETAG);
        CHECK(uut.m_options.read_u16()  == 8); // Length
        CHECK(uut.m_options.read_u64()  == 0xCA0C);
        uut.m_options.read_finalize();
        CHECK(uut.m_options.get_read_ready() == 0);
        // Check the message data
        CHECK(satcat5::test::read(uut.read_data(), "OK"));
    }

    // Read a packet with very long options.
    SECTION("read_long") {
        // Start reading the message header.
        ArrayRead msg(EXAMPLE_LONG, sizeof(EXAMPLE_LONG));
        TestReader uut(&msg);
        uut.read_options();
        // 1st option = Option 13 with 13 data bytes.
        // (Using the 1-byte extended length for both sub-fields.)
        REQUIRE(uut.m_options.get_read_ready() > 0);
        CHECK(uut.m_options.read_u16()  == 13);
        CHECK(uut.m_options.read_u16()  == 13);
        CHECK(uut.m_options.get_read_ready() == 13);
        uut.m_options.read_finalize();
        // 2nd option = Option 4942 (13 + 0x1234), with 5 data bytes.
        // (Using the 2-byte extended length for the ID-delta.)
        REQUIRE(uut.m_options.get_read_ready() > 0);
        CHECK(uut.m_options.read_u16()  == 4942);
        CHECK(uut.m_options.read_u16()  == 5);
        CHECK(uut.m_options.get_read_ready() == 5);
        uut.m_options.read_finalize();
        // 3rd option is longer than the input -> error.
        CHECK(uut.error());
        CHECK(uut.error_code() == satcat5::coap::CODE_BAD_OPTION);
        CHECK(uut.m_options.get_read_ready() == 0);
        CHECK_FALSE(uut.read_data());
    }

    // Read a packet with an invalid initial header.
    SECTION("read_bad_hdr") {
        // The error flag should be set as soon as we read the header.
        ArrayRead msg(EXAMPLE_BAD_HDR, sizeof(EXAMPLE_BAD_HDR));
        satcat5::coap::Reader uut(&msg);
        CHECK(uut.error());
    }

    // Read a packet with an invalid option ID.
    SECTION("read_bad_id") {
        // Start reading the message header and confirm decode failure.
        ArrayRead msg(EXAMPLE_BAD_ID, sizeof(EXAMPLE_BAD_ID));
        satcat5::coap::Reader uut(&msg);
        CHECK_FALSE(uut.error());
        uut.read_options();
        CHECK(uut.error());
        CHECK_FALSE(uut.read_data());
    }

    SECTION("read_empty") {
        // Read an empty CON message without a token (aka "ping").
        ArrayRead msg1(EXAMPLE_EMPTY_VALID, sizeof(EXAMPLE_EMPTY_VALID));
        satcat5::coap::Reader uut1(&msg1);
        CHECK_FALSE(uut1.error());
        // Read an empty message with a token (error per Section 4.1).
        ArrayRead msg2(EXAMPLE_EMPTY_TOKEN, sizeof(EXAMPLE_EMPTY_TOKEN));
        satcat5::coap::Reader uut2(&msg2);
        CHECK(uut2.error());
    }

    SECTION("read_no_data") {
        // Start reading the message header.
        ArrayRead msg(EXAMPLE_NO_DATA, sizeof(EXAMPLE_NO_DATA));
        satcat5::coap::Reader uut(&msg);
        uut.read_options();
        // No options and no data.
        CHECK_FALSE(uut.error());
        CHECK_FALSE(uut.uri_path());
        CHECK_FALSE(uut.format());
        CHECK_FALSE(uut.size1());
        CHECK(satcat5::test::read(uut.read_data(), ""));
    }

    SECTION("read_unknown_critical") {
        // Create a message with an unknown Critical (odd ID) option
        ArrayRead msg(EXAMPLE_UNKNOWN_CRIT, sizeof(EXAMPLE_UNKNOWN_CRIT));
        satcat5::coap::Reader uut(&msg);
        uut.read_options();
        CHECK(uut.error());
        CHECK(uut.error_code() == satcat5::coap::CODE_BAD_OPTION);
    }

    SECTION("read_longest_uri") {
        // Create a message with a maximum length nested Uri-Path.
        satcat5::io::ArrayWriteStatic<256> wr_msg;
        wr_msg.write_bytes(8, EXAMPLE_QUERY); // Copy header up to options
        const std::string uri_path_1 = "longlonglong";
        wr_msg.write_u8((11 << 4) | uri_path_1.size()); // Uri-Path
        wr_msg.write_str(uri_path_1.c_str());
        const std::string uri_path_2 = "longlonglong";
        wr_msg.write_u8(uri_path_2.size()); // Delta = 0, length only
        wr_msg.write_str(uri_path_2.c_str());
        const size_t max_len = SATCAT5_COAP_MAX_URI_PATH_LEN;
        std::string full_path = uri_path_1 + "/" + uri_path_2;
        const size_t n_rep = max_len - (full_path + "/").length();
        const std::string uri_path_3(n_rep, 'l');
        if (uri_path_3.size() < 13) {
            wr_msg.write_u8(uri_path_3.size());
        } else {
            wr_msg.write_u8(13); wr_msg.write_u8(uri_path_3.size() - 13);
        }
        wr_msg.write_str(uri_path_3.c_str());
        wr_msg.write_finalize();
        full_path += "/" + uri_path_3;

        // Confirm the Uri-Path can be successfully parsed.
        ArrayRead msg(wr_msg.buffer(), wr_msg.written_len());
        satcat5::coap::Reader uut(&msg);
        uut.read_options();
        CHECK_FALSE(uut.error());
        CHECK(uut.uri_path());
        CHECK(strcmp(uut.uri_path().value(), full_path.c_str()) == 0);
    }

    SECTION("resource_too_long") {
        // Create a message with an oversized Uri-Path.
        satcat5::io::ArrayWriteStatic<256> wr_msg;
        wr_msg.write_bytes(8, EXAMPLE_QUERY); // Copy header up to options
        const std::string uri_path_1 = "longlonglong";
        wr_msg.write_u8((satcat5::coap::OPTION_URI_PATH << 4) | uri_path_1.size());
        wr_msg.write_str(uri_path_1.c_str());
        const std::string uri_path_2 = "longlonglong";
        wr_msg.write_u8(uri_path_2.size());
        wr_msg.write_str(uri_path_2.c_str());
        const size_t max_len = SATCAT5_COAP_MAX_URI_PATH_LEN;
        const size_t n_rep = max_len - (uri_path_1 + uri_path_2).length() - 1;
        const std::string uri_path_3(n_rep, 'l');
        if (uri_path_3.size() < 13) {
            wr_msg.write_u8(uri_path_3.size());
        } else {
            wr_msg.write_u8(13); wr_msg.write_u8(uri_path_3.size() - 13);
        }
        wr_msg.write_str(uri_path_3.c_str());
        wr_msg.write_finalize();

        // Confirm the Reader returns the correct error code.
        ArrayRead msg(wr_msg.buffer(), wr_msg.written_len());
        satcat5::coap::Reader uut(&msg);
        uut.read_options();
        CHECK(uut.error());
        CHECK(uut.error_code() == satcat5::coap::CODE_BAD_OPTION);
    }

    SECTION("read_size1") {
        // Confirm the Size1 field is parsed
        ArrayRead msg(EXAMPLE_SIZE1, sizeof(EXAMPLE_SIZE1));
        satcat5::coap::Reader uut(&msg);
        uut.read_options();
        CHECK_FALSE(uut.error());
        CHECK(uut.size1());
        CHECK(uut.size1().value() == 1500);
        CHECK(satcat5::test::read(uut.read_data(), ""));
    }
}

TEST_CASE("coap_writer") {
    SATCAT5_TEST_START;

    // Create backing buffer and the unit under test.
    satcat5::io::PacketBufferHeap buf;
    satcat5::coap::Writer uut(&buf, false); // Max-Age not inserted
    REQUIRE(uut.ready());

    // Reconstruct the example query.
    SECTION("write_query") {
        // Write header, options, and message.
        CHECK(uut.write_header(
            satcat5::coap::TYPE_CON,
            satcat5::coap::CODE_POST,
            0xA894, 0x7D5B825D));
        CHECK(uut.write_option(
            satcat5::coap::OPTION_URI_PATH, "logs"));
        CHECK(uut.write_option(
            satcat5::coap::OPTION_FORMAT, satcat5::coap::FORMAT_JSON));
        CHECK(satcat5::test::write(uut.write_data(), EXAMPLE_JSON));
        // Confirm the result is identical to the reference.
        CHECK(satcat5::test::read(&buf, sizeof(EXAMPLE_QUERY), EXAMPLE_QUERY));
    }

    // Reconstruct the example response.
    SECTION("write_response") {
        // Write header, options, and message.
        CHECK(uut.write_header(
            satcat5::coap::TYPE_ACK,
            satcat5::coap::CODE_VALID,
            0xA894, 0x7D5B825D));
        CHECK(uut.write_option(
            satcat5::coap::OPTION_ETAG, 8,
            "\x00\x00\x00\x00\x00\x00\xCA\x0C"));
        CHECK(uut.write_option(
            satcat5::coap::OPTION_FORMAT, satcat5::coap::FORMAT_TEXT));
        CHECK(satcat5::test::write(uut.write_data(), "OK"));
        // Confirm the result is identical to the reference.
        CHECK(satcat5::test::read(&buf, sizeof(EXAMPLE_RESPONSE), EXAMPLE_RESPONSE));
    }

    // Write and read back the extended-length option headers.
    // (ID-delta and length of >13 and >269, respectively.)
    SECTION("write_long") {
        const u8 LONG_MSG[321] = {0xAB};
        // Write header, options, and message.
        CHECK(uut.write_header(
            satcat5::coap::TYPE_CON,
            satcat5::coap::CODE_PUT,
            0x1234, 0xDEADBEEFCAFEull));
        const std::string med_str = "medium_length_string";
        CHECK(uut.write_option(42, med_str.c_str()));
        CHECK(uut.write_option(1234, sizeof(LONG_MSG), LONG_MSG));
        CHECK(satcat5::test::write(uut.write_data(), sizeof(LONG_MSG), LONG_MSG));
        // Parse the constructed message.
        TestReader uut(&buf);
        uut.read_options();
        CHECK_FALSE(uut.error());
        CHECK(uut.type()        == satcat5::coap::TYPE_CON);
        CHECK(uut.tkl()         == 6);
        CHECK(uut.code()        == satcat5::coap::CODE_PUT);
        CHECK(uut.msg_id()      == 0x1234);
        CHECK(uut.token()       == 0xDEADBEEFCAFEull);
        // 1st option = "medium_length_string"
        REQUIRE(uut.m_options.get_read_ready() > 0);
        CHECK(uut.m_options.read_u16()  == 42);
        CHECK(uut.m_options.read_u16()  == med_str.length());
        CHECK(satcat5::test::read(&uut.m_options, med_str)); // Calls finalize()
        // 2nd option = LONG_MSG
        REQUIRE(uut.m_options.get_read_ready() > 0);
        CHECK(uut.m_options.read_u16()  == 1234);
        CHECK(uut.m_options.read_u16()  == sizeof(LONG_MSG));
        CHECK(satcat5::test::read(&uut.m_options, sizeof(LONG_MSG), LONG_MSG));
        // Next block should be the message data.
        CHECK(uut.m_options.get_read_ready() == 0);
        CHECK(satcat5::test::read(uut.read_data(), sizeof(LONG_MSG), LONG_MSG));
    }

    // Write and read a packet with options but no data.
    SECTION("write_no_data") {
        // Write header, options, and message.
        CHECK(uut.write_header(
            satcat5::coap::TYPE_CON,
            satcat5::coap::CODE_PUT,
            0x1234, 0xDEADBEEFCAFEull));
        CHECK(uut.write_option(
            satcat5::coap::OPTION_URI_PATH, "no_data"));
        CHECK(uut.write_finalize());
        // Parse the constructed message.
        satcat5::coap::Reader uut(&buf);
        CHECK_FALSE(uut.error());
        CHECK(uut.type()        == satcat5::coap::TYPE_CON);
        CHECK(uut.tkl()         == 6);
        CHECK(uut.code()        == satcat5::coap::CODE_PUT);
        CHECK(uut.msg_id()      == 0x1234);
        CHECK(uut.token()       == 0xDEADBEEFCAFEull);
        // Confirm the Uri-Path option and that there are no extra options
        CHECK(uut.uri_path());
        CHECK(strcmp(uut.uri_path().value(), "no_data") == 0);
        // Data field should be empty.
        CHECK(satcat5::test::read(uut.read_data(), ""));
    }

    // Write and read a short packet with no options.
    SECTION("write_no_options") {
        // Write header, options, and message.
        CHECK(uut.write_header(
            satcat5::coap::TYPE_CON,
            satcat5::coap::CODE_PUT,
            0x1234, 0xDEADBEEFCAFEull, 5)); // Intentionally truncate
        CHECK(satcat5::test::write(uut.write_data(), EXAMPLE_JSON));
        // Parse the constructed message.
        satcat5::coap::Reader uut(&buf);
        CHECK_FALSE(uut.error());
        CHECK(uut.type()        == satcat5::coap::TYPE_CON);
        CHECK(uut.tkl()         == 5);      // Truncated
        CHECK(uut.code()        == satcat5::coap::CODE_PUT);
        CHECK(uut.msg_id()      == 0x1234);
        CHECK(uut.token()       == 0xADBEEFCAFEull);
        CHECK_FALSE(uut.uri_path());
        CHECK_FALSE(uut.format());
        CHECK_FALSE(uut.size1());
        CHECK(satcat5::test::read(uut.read_data(), EXAMPLE_JSON));
    }
}

TEST_CASE("coap_writer_auto_insert") {
    SATCAT5_TEST_START;

    // Create backing buffer and the unit under test.
    satcat5::io::PacketBufferHeap buf;
    satcat5::coap::Writer uut(&buf, true); // Max-Age automatically inserted
    REQUIRE(uut.ready());

    // Write an empty packet and confirm nothing is auto-inserted
    SECTION("empty") {
        CHECK(uut.write_header(
            satcat5::coap::TYPE_CON, satcat5::coap::CODE_EMPTY, 0xA894));
        CHECK(uut.write_finalize());
        satcat5::coap::Reader uut(&buf); // Skip header
        CHECK_FALSE(uut.error());
        CHECK(buf.get_read_ready()  == 0);
        buf.read_finalize();
    }

    // Write an ack packet and confirm Max-Age=0 is auto-inserted
    SECTION("ack") {
        CHECK(uut.write_header(
            satcat5::coap::TYPE_CON, satcat5::coap::CODE_GET, 0xA894));
        CHECK(uut.write_finalize());
        satcat5::coap::Reader uut(&buf);
        CHECK_FALSE(uut.error());
        CHECK(buf.read_u8()         == (13 << 4)); // u8 ID
        CHECK(buf.read_u8()         == satcat5::coap::OPTION_MAX_AGE - 13);
        CHECK(buf.get_read_ready()  == 0);
        buf.read_finalize();
    }

    // Write a packet with many options and no data
    SECTION("no_data") {
        CHECK(uut.write_header(
            satcat5::coap::TYPE_CON, satcat5::coap::CODE_GET, 0xA894));
        CHECK(uut.write_option(satcat5::coap::OPTION_ETAG, 0x1234));
        CHECK(uut.write_option(satcat5::coap::OPTION_SIZE1, 1500));
        CHECK(uut.write_finalize());
        satcat5::coap::Reader uut(&buf);
        CHECK_FALSE(uut.error());
        CHECK(buf.read_u8()         == ((satcat5::coap::OPTION_ETAG << 4) | 2));
        CHECK(buf.read_u16()        == 0x1234);
        int delta = satcat5::coap::OPTION_MAX_AGE - satcat5::coap::OPTION_ETAG;
        CHECK(buf.read_u8()         == (delta << 4)); // Max-Age=0
        delta = satcat5::coap::OPTION_SIZE1 - satcat5::coap::OPTION_MAX_AGE;
        CHECK(buf.read_u8()         == ((13 << 4) | 2));
        CHECK(buf.read_u8()         == delta - 13);
        CHECK(buf.read_u16()        == 1500);
        CHECK(buf.get_read_ready()  == 0);
        buf.read_finalize();
    }

    // Write a packet with Max-Age overridden
    SECTION("override") {
        CHECK(uut.write_header(
            satcat5::coap::TYPE_CON, satcat5::coap::CODE_GET, 0xA894));
        CHECK(uut.write_option(satcat5::coap::OPTION_MAX_AGE, 30));
        CHECK(uut.write_option(satcat5::coap::OPTION_SIZE1, 1500));
        CHECK(uut.write_finalize());
        satcat5::coap::Reader uut(&buf);
        CHECK_FALSE(uut.error());
        CHECK(buf.read_u8()         == ((13 << 4) | 1));
        CHECK(buf.read_u8()         == satcat5::coap::OPTION_MAX_AGE - 13);
        CHECK(buf.read_u8()         == 30); // Max-Age=30
        int delta = satcat5::coap::OPTION_SIZE1 - satcat5::coap::OPTION_MAX_AGE;
        CHECK(buf.read_u8()         == ((13 << 4) | 2));
        CHECK(buf.read_u8()         == delta - 13);
        CHECK(buf.read_u16()        == 1500);
        CHECK(buf.get_read_ready()  == 0);
        buf.read_finalize();
    }

    // Write a packet with no options and a payload
    SECTION("no_options") {
        CHECK(uut.write_header(
            satcat5::coap::TYPE_CON, satcat5::coap::CODE_GET, 0xA894));
        CHECK(satcat5::test::write(uut.write_data(), EXAMPLE_JSON));
        satcat5::coap::Reader uut(&buf);
        CHECK_FALSE(uut.error());
        CHECK(buf.read_u8()         == (13 << 4));
        CHECK(buf.read_u8()         == satcat5::coap::OPTION_MAX_AGE - 13);
        CHECK(satcat5::test::read(uut.read_data(), EXAMPLE_JSON));
    }
}
