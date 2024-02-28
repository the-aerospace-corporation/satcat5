//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for CRC16 checksum functions

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/crc16_checksum.h>
#include <satcat5/utils.h>
#include <vector>

using satcat5::test::write;
using satcat5::test::read;
typedef std::vector<u8> Packet;

// Known-good KERMIT reference packets:
// https://reveng.sourceforge.io/crc-catalogue/16.htm#crc.cat.crc-16-kermit
static const Packet REF_K1 = {0x54, 0xA1, 0x14};
static const Packet REF_K2 = {
    0x43, 0xAE, 0xD6, 0xC8, 0xAD, 0xD6, 0x51, 0x43,
    0x15, 0x51, 0xB0, 0x31, 0x02, 0xD3, 0x32, 0xB9,
    0xC1, 0xD6, 0x51, 0x31, 0x37, 0x32, 0xB5, 0x83,
    0xF3, 0x03};
static const Packet REF_K3 = {
    0x6D, 0xAE, 0xB9, 0xCD, 0xAD, 0xCD, 0x52, 0x4F,
    0x15, 0xC1, 0xC1, 0x54, 0x02, 0x2F, 0xCD, 0x45,
    0x4C, 0x43, 0xC1, 0xD9, 0xC1, 0xAE, 0xC1, 0x54,
    0x31, 0xAE, 0xB9, 0xCD, 0xAD, 0xCD, 0x52, 0x4F,
    0x32, 0xB0, 0xB9, 0x34, 0x46, 0xC2, 0xC1, 0x34,
    0x43, 0xB0, 0xB3, 0xB9, 0xB9, 0x46, 0x83, 0x48,
    0x61};
static const Packet REF_K4 = {
    0xCD, 0xAE, 0xB9, 0xCD, 0xAD, 0xCD, 0x52, 0x4F,
    0x54, 0xDF, 0x7F, 0x38, 0x02, 0xD3, 0x32, 0x31,
    0xC1, 0xCD, 0xC8, 0xB0, 0x31, 0x34, 0x38, 0x83,
    0x61, 0xA7};
static const Packet REF_K5 = {
    0x43, 0x61, 0x74, 0x4D, 0x6F, 0x75, 0x73, 0x65,
    0x39, 0x38, 0x37, 0x36, 0x35, 0x34, 0x33, 0x32,
    0x31, 0x8D, 0xC2};

// Known-good XMODEM reference packets:
// https://reveng.sourceforge.io/crc-catalogue/16.htm#crc.cat.crc-16-xmodem
static const Packet REF_X1 = {0x54, 0x1A, 0x71};
static const Packet REF_X2 = {
    0x43, 0x61, 0x74, 0x4D, 0x6F, 0x75, 0x73, 0x65,
    0x39, 0x38, 0x37, 0x36, 0x35, 0x34, 0x33, 0x32,
    0x31, 0xE5, 0x56};

// Pointer to packet contents.
inline const u8* ptr(const Packet& pkt) {return &pkt[0];}

// Length of a packet, with or without appended 16-bit CRC.
inline unsigned len1(const Packet& pkt) {return pkt.size() - 2;}
inline unsigned len2(const Packet& pkt) {return pkt.size();}

// Read the last two bytes from a complete packet.
inline u16 read_crc(const Packet& pkt)
    {return satcat5::util::extract_be_u16(ptr(pkt) + len1(pkt));}

TEST_CASE("crc16-kermit") {
    // All units under test write to the same buffer.
    satcat5::io::PacketBufferHeap buff;
    satcat5::crc16::KermitRx uut_rx(&buff);
    satcat5::crc16::KermitTx uut_tx(&buff);

    // Repeat every test for each of the example packets...
    auto pkt = GENERATE(REF_K1, REF_K2, REF_K3, REF_K4, REF_K5);

    // Confirm that direct calculation generates the expected CRC.
    SECTION("direct") {
        CHECK(satcat5::crc16::kermit(len1(pkt), ptr(pkt)) == read_crc(pkt));
    }

    // Send the complete packet to the receiver, which should pass it through.
    SECTION("rx-good") {
        CHECK(write(&uut_rx, len2(pkt), ptr(pkt)));
        CHECK(read(&buff, len1(pkt), ptr(pkt)));
    }

    // Send a truncated packet to the receiver, which should reject it.
    SECTION("rx-bad") {
        CHECK_FALSE(write(&uut_rx, len2(pkt)-1, ptr(pkt)));
        CHECK(buff.get_read_ready() == 0);
    }

    // Send a packet that's so short it cannot be valid.
    SECTION("rx-runt") {
        CHECK_FALSE(write(&uut_rx, 1, ptr(pkt)));
        CHECK(buff.get_read_ready() == 0);
    }

    // Test that the transmitter generates the expected CRC.
    SECTION("tx") {
        CHECK(write(&uut_tx, len1(pkt), ptr(pkt)));
        CHECK(read(&buff, len2(pkt), ptr(pkt)));
    }
}

TEST_CASE("crc16-xmodem") {
    // All units under test write to the same buffer.
    satcat5::io::PacketBufferHeap buff;
    satcat5::crc16::XmodemRx uut_rx(&buff);
    satcat5::crc16::XmodemTx uut_tx(&buff);

    // Repeat every test for each of the example packets...
    auto pkt = GENERATE(REF_X1, REF_X2);

    // Confirm that direct calculation generates the expected CRC.
    SECTION("direct") {
        CHECK(satcat5::crc16::xmodem(len1(pkt), ptr(pkt)) == read_crc(pkt));
    }

    // Send the complete packet to the receiver, which should pass it through.
    SECTION("rx-good") {
        CHECK(write(&uut_rx, len2(pkt), ptr(pkt)));
        CHECK(read(&buff, len1(pkt), ptr(pkt)));
    }

    // Send a truncated packet to the receiver, which should reject it.
    SECTION("rx-bad") {
        CHECK_FALSE(write(&uut_rx, len2(pkt)-1, ptr(pkt)));
        CHECK(buff.get_read_ready() == 0);
    }

    // Send a packet that's so short it cannot be valid.
    SECTION("rx-runt") {
        CHECK_FALSE(write(&uut_rx, 1, ptr(pkt)));
        CHECK(buff.get_read_ready() == 0);
    }

    // Test that the transmitter generates the expected CRC.
    SECTION("tx") {
        CHECK(write(&uut_tx, len1(pkt), ptr(pkt)));
        CHECK(read(&buff, len2(pkt), ptr(pkt)));
    }
}
