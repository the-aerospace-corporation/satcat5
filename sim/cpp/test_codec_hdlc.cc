//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the HDLC-framing encoder and decoder.

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/codec_hdlc.h>

// Known-good HDLC reference packet using 16-bit CRC mode:
// https://stackoverflow.com/questions/7983862/calculating-fcscrc-for-hdlc-frame
static const u8 EXAMPLE_DAT[] = {
    0x01, 0x00, 0x00, 0x01, 0x00, 0x18, 0xEF, 0x00,
    0x00, 0x00, 0xB5, 0x20, 0xC1, 0x05, 0x10, 0x02,
    0x71, 0x2E, 0x1A, 0xC2, 0x05, 0x10, 0x01, 0x71,
    0x00, 0x6E, 0x87, 0x02, 0x00, 0x01, 0x42, 0x71,
    0x2E, 0x1A, 0x01, 0x96, 0x27, 0xBE, 0x27, 0x54,
    0x17, 0x3D, 0xB9};
static const u8 EXAMPLE_ENC[] = {
    0x01, 0x00, 0x00, 0x01, 0x00, 0x18, 0xEF, 0x00,
    0x00, 0x00, 0xB5, 0x20, 0xC1, 0x05, 0x10, 0x02,
    0x71, 0x2E, 0x1A, 0xC2, 0x05, 0x10, 0x01, 0x71,
    0x00, 0x6E, 0x87, 0x02, 0x00, 0x01, 0x42, 0x71,
    0x2E, 0x1A, 0x01, 0x96, 0x27, 0xBE, 0x27, 0x54,
    0x17, 0x3D, 0xB9, 0x93, 0xAC, 0x7E};

TEST_CASE("HdlcEncoder") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Unit under test writes encoded stream to a buffer.
    satcat5::io::PacketBufferHeap tx(200);
    satcat5::io::HdlcEncoder uut(&tx);
    REQUIRE(uut.get_write_space() > 4);

    SECTION("simple4_crc32") {
        uut.set_mode_actrl(false);
        uut.set_mode_crc32(true);
        uut.write_u32(0x12345678u);
        REQUIRE(uut.write_finalize());
        REQUIRE(tx.get_read_ready() == 9);
        CHECK(tx.read_u8() == 0x12);     // Data
        CHECK(tx.read_u8() == 0x34);
        CHECK(tx.read_u8() == 0x56);
        CHECK(tx.read_u8() == 0x78);
        CHECK(tx.read_u8() == 0x98);     // CRC32
        CHECK(tx.read_u8() == 0x0E);
        CHECK(tx.read_u8() == 0x09);
        CHECK(tx.read_u8() == 0x4A);
        CHECK(tx.read_u8() == 0x7E);     // EOF
    }

    SECTION("escape4_crc32") {
        uut.set_mode_actrl(true);
        uut.set_mode_crc32(true);
        uut.write_u32(0x7D01237Eu);
        REQUIRE(uut.write_finalize());
        REQUIRE(tx.get_read_ready() == 12);
        CHECK(tx.read_u8() == 0x7D);     // Escape (ESC token)
        CHECK(tx.read_u8() == 0x5D);
        CHECK(tx.read_u8() == 0x7D);     // Escape (Data < 0x20)
        CHECK(tx.read_u8() == 0x21);
        CHECK(tx.read_u8() == 0x23);
        CHECK(tx.read_u8() == 0x7D);     // Escape (END token)
        CHECK(tx.read_u8() == 0x5E);
        CHECK(tx.read_u8() == 0x30);     // CRC32
        CHECK(tx.read_u8() == 0xE6);
        CHECK(tx.read_u8() == 0xC7);
        CHECK(tx.read_u8() == 0xB0);
        CHECK(tx.read_u8() == 0x7E);     // EOF
    }

    SECTION("known_good_crc16") {
        uut.set_mode_actrl(false);
        uut.set_mode_crc32(false);
        uut.write_bytes(sizeof(EXAMPLE_DAT), EXAMPLE_DAT);
        REQUIRE(uut.write_finalize());
        CHECK(satcat5::test::read(&tx, sizeof(EXAMPLE_ENC), EXAMPLE_ENC));
    }

    SECTION("overflow") {
        unsigned write_len = tx.get_write_space() + 10;
        uut.set_mode_actrl(false);
        uut.set_mode_crc32(true);
        for (unsigned a = 0 ; a < write_len ; ++a)
            uut.write_u8(a & 0xFF);
        CHECK_FALSE(uut.write_finalize());
    }
}

TEST_CASE("HdlcDecoder") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Unit under test writes decoded frames to a buffer.
    satcat5::io::PacketBufferHeap rx(200);
    satcat5::io::HdlcDecoder uut(&rx);

    SECTION("simple4_crc32") {
        uut.set_mode_actrl(false);
        uut.set_mode_crc32(true);
        uut.write_bytes(9, "\x12\x34\x56\x78\x98\x0E\x09\x4A\x7E");
        REQUIRE(rx.get_read_ready() == 4);
        CHECK(rx.read_u32() == 0x12345678u);
        rx.read_finalize();
    }

    SECTION("escape4_crc32") {
        uut.set_mode_actrl(true);
        uut.set_mode_crc32(true);
        uut.write_bytes(12, "\x7D\x5D\x7D\x21\x23\x7D\x5E\x30\xE6\xC7\xB0\x7E");
        REQUIRE(rx.get_read_ready() == 4);
        CHECK(rx.read_u32() == 0x7D01237Eu);
        rx.read_finalize();
    }

    SECTION("known_good_crc16") {
        uut.set_mode_actrl(false);
        uut.set_mode_crc32(false);
        uut.write_bytes(sizeof(EXAMPLE_ENC), EXAMPLE_ENC);
        CHECK(satcat5::test::read(&rx, sizeof(EXAMPLE_DAT), EXAMPLE_DAT));
    }

    SECTION("overflow") {
        unsigned write_len = rx.get_write_space() + 10;
        uut.set_mode_actrl(false);
        uut.set_mode_crc32(true);
        for (unsigned a = 0 ; a < write_len ; ++a)
            uut.write_u8(0x42);                     // Packet too long...
        uut.write_u8(0x7E);                         // End-of-frame
        CHECK(rx.get_read_ready() == 0);            // Confirm output is empty
        uut.write_bytes(9, "\x12\x34\x56\x78\x98\x0E\x09\x4A\x7E");
        CHECK(rx.get_read_ready() == 4);            // Confirm output is OK
    }
}
