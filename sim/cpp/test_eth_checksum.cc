//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// Test cases for Ethernet checksum functions

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_checksum.h>

using satcat5::test::write;
using satcat5::test::read;

// Known-good reference packet #1:
// (Original 60 bytes / 64 with FCS / 65 with FCS+SLIP)
// https://www.cl.cam.ac.uk/research/srg/han/ACS-P35/ethercrc/
static const u32 REF1_CRC = 0x9ED2C2AF;
static const u8 REF1A[] = {
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x20,
    0xAF, 0xB7, 0x80, 0xB8, 0x08, 0x06, 0x00, 0x01,
    0x08, 0x00, 0x06, 0x04, 0x00, 0x01, 0x00, 0x20,
    0xAF, 0xB7, 0x80, 0xB8, 0x80, 0xE8, 0x0F, 0x94,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0xE8,
    0x0F, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE,
    0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE,
    0xDE, 0xDE, 0xDE, 0xDE};
static const u8 REF1B[] = {
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x20,
    0xAF, 0xB7, 0x80, 0xB8, 0x08, 0x06, 0x00, 0x01,
    0x08, 0x00, 0x06, 0x04, 0x00, 0x01, 0x00, 0x20,
    0xAF, 0xB7, 0x80, 0xB8, 0x80, 0xE8, 0x0F, 0x94,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0xE8,
    0x0F, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE,
    0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE,
    0xDE, 0xDE, 0xDE, 0xDE, 0x9E, 0xD2, 0xC2, 0xAF};
static const u8 REF1C[] = {
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x20,
    0xAF, 0xB7, 0x80, 0xB8, 0x08, 0x06, 0x00, 0x01,
    0x08, 0x00, 0x06, 0x04, 0x00, 0x01, 0x00, 0x20,
    0xAF, 0xB7, 0x80, 0xB8, 0x80, 0xE8, 0x0F, 0x94,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0xE8,
    0x0F, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE,
    0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE, 0xDE,
    0xDE, 0xDE, 0xDE, 0xDE, 0x9E, 0xD2, 0xC2, 0xAF,
    0xC0};

// Known-good reference packet #2:
// (Original 60 bytes / 64 with FCS / 66 with FCS+SLIP)
// https://electronics.stackexchange.com/questions/170612/fcs-verification-of-ethernet-frame
static const u32 REF2_CRC = 0x9BF6D0FD;
static const u8 REF2A[] = {
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00,
    0x00, 0x04, 0x14, 0x13, 0x08, 0x00, 0x45, 0x00,
    0x00, 0x2E, 0x00, 0x00, 0x00, 0x00, 0x40, 0x11,
    0x7A, 0xC0, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF,
    0xFF, 0xFF, 0x00, 0x00, 0x50, 0xDA, 0x00, 0x12,
    0x00, 0x00, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
    0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
    0x42, 0x42, 0x42, 0x42};
static const u8 REF2B[] = {
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00,
    0x00, 0x04, 0x14, 0x13, 0x08, 0x00, 0x45, 0x00,
    0x00, 0x2E, 0x00, 0x00, 0x00, 0x00, 0x40, 0x11,
    0x7A, 0xC0, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF,
    0xFF, 0xFF, 0x00, 0x00, 0x50, 0xDA, 0x00, 0x12,
    0x00, 0x00, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
    0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
    0x42, 0x42, 0x42, 0x42, 0x9B, 0xF6, 0xD0, 0xFD};
static const u8 REF2C[] = {
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00,
    0x00, 0x04, 0x14, 0x13, 0x08, 0x00, 0x45, 0x00,
    0x00, 0x2E, 0x00, 0x00, 0x00, 0x00, 0x40, 0x11,
    0x7A, 0xDB, 0xDC, 0x00, 0x00, 0x00, 0x00, 0xFF,
    0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x50, 0xDA, 0x00,
    0x12, 0x00, 0x00, 0x42, 0x42, 0x42, 0x42, 0x42,
    0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
    0x42, 0x42, 0x42, 0x42, 0x42, 0x9B, 0xF6, 0xD0,
    0xFD, 0xC0};

TEST_CASE("eth-checksum-raw") {
    SECTION("crc32-array") {
        // Call crc32() on each raw example array.
        CHECK(satcat5::eth::crc32(sizeof(REF1A), REF1A) == REF1_CRC);
        CHECK(satcat5::eth::crc32(sizeof(REF2A), REF2A) == REF2_CRC);
    }

    SECTION("crc32-readable") {
        // Call crc32() on a Readable object for each example.
        auto ref1 = satcat5::io::ArrayRead(REF1A, sizeof(REF1A));
        auto ref2 = satcat5::io::ArrayRead(REF2A, sizeof(REF2A));
        CHECK(satcat5::eth::crc32(&ref1) == REF1_CRC);
        CHECK(satcat5::eth::crc32(&ref2) == REF2_CRC);
    }
}

TEST_CASE("eth-checksum-tx") {
    satcat5::log::ToConsole log;
    satcat5::io::PacketBufferHeap rx;
    satcat5::eth::ChecksumTx uut(&rx);

    SECTION("fixed-ref") {
        // Write each reference without FCS.
        CHECK(write(&uut, sizeof(REF1A), REF1A));
        CHECK(write(&uut, sizeof(REF2A), REF2A));
        // Expect matching references with FCS.
        CHECK(read(&rx, sizeof(REF1B), REF1B));
        CHECK(read(&rx, sizeof(REF2B), REF2B));
    }

    SECTION("abort-then-write") {
        // Write some junk, abort, then try again.
        uut.write_bytes(sizeof(REF1A), REF1A);
        uut.write_abort();
        uut.write_bytes(sizeof(REF2A), REF2A);
        CHECK(uut.write_finalize());
        // Expect only the second packet, with FCS.
        CHECK(read(&rx, sizeof(REF2B), REF2B));
    }
}

TEST_CASE("eth-checksum-rx") {
    satcat5::log::ToConsole log;
    satcat5::io::PacketBufferHeap rx;
    satcat5::eth::ChecksumRx uut(&rx);

    SECTION("fixed-ref") {
        // Write each reference with FCS.
        CHECK(write(&uut, sizeof(REF1B), REF1B));
        CHECK(write(&uut, sizeof(REF2B), REF2B));
        // Expect matching references without FCS.
        CHECK(read(&rx, sizeof(REF1A), REF1A));
        CHECK(read(&rx, sizeof(REF2A), REF2A));
    }

    SECTION("bad-fcs") {
        // Write Ref1 but skip the first byte.
        CHECK_FALSE(write(&uut, sizeof(REF1B) - 1, REF1B + 1));
        // Write Ref2 but skip the last byte.
        CHECK_FALSE(write(&uut, sizeof(REF2B) - 1, REF2B));
        CHECK(rx.get_read_ready() == 0);    // Should remain empty
    }

    SECTION("runt-pkt") {
        // Write only the first three bytes of Ref1.
        CHECK_FALSE(write(&uut, 3, REF1B)); // Should fail (runt packet)
        CHECK(rx.get_read_ready() == 0);    // Should remain empty
    }

    SECTION("abort-then-write") {
        // Write some junk, abort, then try again.
        uut.write_bytes(sizeof(REF1B), REF1B);
        uut.write_abort();
        uut.write_bytes(sizeof(REF2B), REF2B);
        CHECK(uut.write_finalize());
        // Expect only the second packet, minus FCS.
        CHECK(read(&rx, sizeof(REF2A), REF2A));
    }
}

TEST_CASE("eth-slip-codec") {
    satcat5::log::ToConsole log;
    satcat5::io::PacketBufferHeap tx, rx;
    satcat5::eth::SlipCodec uut(&tx, &rx);

    SECTION("encode") {
        // Write each raw reference, check expected output.
        // (Check one at a time because SLIP output ignores frame-boundaries.)
        CHECK(write(&uut, sizeof(REF1A), REF1A));
        CHECK(read(&tx, sizeof(REF1C), REF1C));
        CHECK(write(&uut, sizeof(REF2A), REF2A));
        CHECK(read(&tx, sizeof(REF2C), REF2C));
    }

    SECTION("decode") {
        // Write each encoded reference.
        CHECK(write(&rx, sizeof(REF1C), REF1C));
        CHECK(write(&rx, sizeof(REF2C), REF2C));
        // Process both packets.
        satcat5::poll::service_all();
        // Expect each original reference.
        CHECK(read(&uut, sizeof(REF1A), REF1A));
        CHECK(read(&uut, sizeof(REF2A), REF2A));
    }
}
