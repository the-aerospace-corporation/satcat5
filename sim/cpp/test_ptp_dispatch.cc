//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for "ptp::dispatch"

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <satcat5/eth_header.h>
#include <satcat5/ip_core.h>
#include <satcat5/ptp_dispatch.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/ptp_client.h>

using satcat5::ptp::Dispatch;
using satcat5::ptp::DispatchTo;

TEST_CASE("ptp_dispatch") {
    satcat5::test::CrosslinkIp xlink;
    Dispatch dispatch(&xlink.eth0, &xlink.net0.m_ip);
    xlink.eth0.ptp_callback(&dispatch);
    const unsigned L2_HEADER_LENGTH = 14;
    const unsigned L3_HEADER_LENGTH = 42;

    SECTION("DispatchTo::BROADCAST_L2") {
        satcat5::io::Writeable* writeable = dispatch.ptp_send(
            DispatchTo::BROADCAST_L2, 0, satcat5::ptp::Header::TYPE_ANNOUNCE);
        CHECK(writeable->write_finalize());

        u8 buf_contents[L2_HEADER_LENGTH];
        xlink.eth1.read_bytes(L2_HEADER_LENGTH, buf_contents);
        xlink.eth1.read_finalize();

        const u8 buf_contents_check[L2_HEADER_LENGTH] = {
            0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xde,
            0xad, 0xbe, 0xef, 0x11, 0x11, 0x88, 0xf7 };

        CHECK(std::memcmp(buf_contents, buf_contents_check, sizeof(buf_contents)) == 0);
        CHECK(dispatch.timer() != 0);
    }

    SECTION("DispatchTo::BROADCAST_L3") {
        satcat5::io::Writeable* writeable = dispatch.ptp_send(
            DispatchTo::BROADCAST_L3, 0, satcat5::ptp::Header::TYPE_ANNOUNCE);
        CHECK(writeable->write_finalize());

        u8 buf_contents[L3_HEADER_LENGTH];
        xlink.eth1.read_bytes(L3_HEADER_LENGTH, buf_contents);
        xlink.eth1.read_finalize();

        const u8 buf_contents_check[L3_HEADER_LENGTH] = {
            0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xde, 0xad,
            0xbe, 0xef, 0x11, 0x11, 0x08, 0x00, 0x45, 0x00,
            0x00, 0x1c, 0x00, 0x00, 0x00, 0x00, 0x80, 0x11,
            0x79, 0x1e, 0xc0, 0xa8, 0x01, 0x0b, 0xff, 0xff,
            0xff, 0xff, 0x01, 0x40, 0x01, 0x40, 0x00, 0x08,
            0x00, 0x00};

        CHECK(std::memcmp(buf_contents, buf_contents_check, sizeof(buf_contents)) == 0);
    }

    SECTION("L2 DispatchTo::REPLY and STORED") {
        // Example L2 test message from Wireshark.
        // Destination address was modified to match CrosslinkIp.
        const u8 test_message_L2_reply[60] = {
            0xde, 0xad, 0xbe, 0xef, 0x11, 0x11, 0x00, 0x80,
            0x63, 0x00, 0x09, 0xba, 0x88, 0xf7, 0x00, 0x02,
            0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x80, 0x63, 0xff, 0xff, 0x00,
            0x09, 0xba, 0x00, 0x02, 0x04, 0x3f, 0x00, 0x00,
            0x00, 0x00, 0x45, 0xb1, 0x11, 0x4b, 0x2e, 0x2d,
            0x85, 0x41, 0x00, 0x00 };

        xlink.eth1.write_bytes(sizeof(test_message_L2_reply), (void*)&test_message_L2_reply);
        CHECK(xlink.eth1.write_finalize());

        satcat5::poll::service_all();

        satcat5::io::Writeable* writeable_reply = dispatch.ptp_send(
            DispatchTo::REPLY, L2_HEADER_LENGTH, satcat5::ptp::Header::TYPE_SYNC);
        CHECK(writeable_reply->write_finalize());

        u8 buf_contents[L2_HEADER_LENGTH];
        xlink.eth1.read_bytes(L2_HEADER_LENGTH, buf_contents);
        xlink.eth1.read_finalize();

        const u8 buf_contents_check[L2_HEADER_LENGTH] = {
            0x00, 0x80, 0x63, 0x00, 0x09, 0xba, 0xde, 0xad,
            0xbe, 0xef, 0x11, 0x11, 0x88, 0xf7 };

        CHECK(std::memcmp(buf_contents, buf_contents_check, sizeof(buf_contents)) == 0);

        dispatch.store_reply_addr();

        satcat5::io::Writeable* writeable_stored = dispatch.ptp_send(
            DispatchTo::STORED, L2_HEADER_LENGTH, satcat5::ptp::Header::TYPE_ANNOUNCE);
        CHECK(writeable_stored->write_finalize());

        xlink.eth1.read_bytes(L2_HEADER_LENGTH, buf_contents);
        xlink.eth1.read_finalize();

        CHECK(std::memcmp(buf_contents, buf_contents_check, sizeof(buf_contents)) == 0);
    }

    SECTION("L3 DispatchTo::REPLY and STORED") {
        // Example L3 test message from Wireshark.
        // Destination mac and ip were modified to match Crosslink.
        const u8 test_message_L3_reply[96] = {
            0xde, 0xad, 0xbe, 0xef, 0x11, 0x11, 0x00, 0x80,
            0x63, 0x00, 0x09, 0xba, 0x08, 0x00, 0x45, 0x00,
            0x00, 0x52, 0x45, 0xaf, 0x00, 0x00, 0x01, 0x11,
            0xd0, 0xd2, 0xc0, 0xa8, 0x02, 0x06, 0xc0, 0xa8,
            0x01, 0x0b, 0x01, 0x3f, 0x01, 0x3f, 0x00, 0x3e,
            0x00, 0x00, 0x12, 0x02, 0x00, 0x36, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80,
            0x63, 0xff, 0xff, 0x00, 0x09, 0xba, 0x00, 0x01,
            0x9e, 0x54, 0x05, 0x0f, 0x00, 0x00, 0x45, 0xb1,
            0x11, 0x5b, 0x22, 0x2c, 0x56, 0x3d, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

        xlink.eth1.write_bytes(sizeof(test_message_L3_reply), test_message_L3_reply);
        CHECK(xlink.eth1.write_finalize());

        satcat5::poll::service_all();

        satcat5::io::Writeable* writeable_reply = dispatch.ptp_send(
            DispatchTo::REPLY, 0, satcat5::ptp::Header::TYPE_DELAY_RESP);
        CHECK(writeable_reply->write_finalize());

        u8 buf_contents[L3_HEADER_LENGTH];
        xlink.eth1.read_bytes(L3_HEADER_LENGTH, buf_contents);
        xlink.eth1.read_finalize();

        const u8 buf_contents_reply_check[L3_HEADER_LENGTH] = {
            0x00, 0x80, 0x63, 0x00, 0x09, 0xba, 0xde, 0xad,
            0xbe, 0xef, 0x11, 0x11, 0x08, 0x00, 0x45, 0x00,
            0x00, 0x1c, 0x00, 0x00, 0x00, 0x00, 0x80, 0x11,
            0xb6, 0x6f, 0xc0, 0xa8, 0x01, 0x0b, 0xc0, 0xa8,
            0x02, 0x06, 0x01, 0x40, 0x01, 0x40, 0x00, 0x08,
            0x00, 0x00};

        CHECK(std::memcmp(buf_contents, buf_contents_reply_check, sizeof(buf_contents)) == 0);

        dispatch.store_reply_addr();

        satcat5::io::Writeable* writeable_stored = dispatch.ptp_send(
            DispatchTo::STORED, 0, satcat5::ptp::Header::TYPE_DELAY_REQ);
        CHECK(writeable_stored->write_finalize());

        xlink.eth1.read_bytes(L3_HEADER_LENGTH, buf_contents);
        xlink.eth1.read_finalize();

        const u8 buf_contents_stored_check[L3_HEADER_LENGTH] = {
            0x00, 0x80, 0x63, 0x00, 0x09, 0xba, 0xde, 0xad,
            0xbe, 0xef, 0x11, 0x11, 0x08, 0x00, 0x45, 0x00,
            0x00, 0x1c, 0x00, 0x01, 0x00, 0x00, 0x80, 0x11,
            0xb6, 0x6e, 0xc0, 0xa8, 0x01, 0x0b, 0xc0, 0xa8,
            0x02, 0x06, 0x01, 0x3f, 0x01, 0x3f, 0x00, 0x08,
            0x00, 0x00 };

        CHECK(std::memcmp(buf_contents, buf_contents_stored_check, sizeof(buf_contents)) == 0);
    }
}
