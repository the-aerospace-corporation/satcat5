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
// Test cases for the SLIP encoder and decoder.

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/slip.h>

TEST_CASE("SlipEncoder") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Create a working buffer for each encoded frame.
    satcat5::io::PacketBufferHeap test_buff(64);

    // Unit under test writes to this buffer.
    satcat5::io::SlipEncoder uut(&test_buff);

    SECTION("simple4") {
        uut.write_u32(0x12345678u);
        uut.write_finalize();
        CHECK(test_buff.get_read_ready() == 5);
        CHECK(test_buff.read_u8() == 0x12);
        CHECK(test_buff.read_u8() == 0x34);
        CHECK(test_buff.read_u8() == 0x56);
        CHECK(test_buff.read_u8() == 0x78);
        CHECK(test_buff.read_u8() == 0xC0);   // EOF
    }

    SECTION("escape4") {
        uut.write_u32(0xDB12C034u);
        uut.write_finalize();
        CHECK(test_buff.get_read_ready() == 7);
        CHECK(test_buff.read_u8() == 0xDB);   // Escape
        CHECK(test_buff.read_u8() == 0xDD);
        CHECK(test_buff.read_u8() == 0x12);
        CHECK(test_buff.read_u8() == 0xDB);   // Escape
        CHECK(test_buff.read_u8() == 0xDC);
        CHECK(test_buff.read_u8() == 0x34);
        CHECK(test_buff.read_u8() == 0xC0);   // EOF
    }

    SECTION("overflow") {
        for (u8 a = 0 ; a < 64 ; ++a)
            uut.write_u8(a);
        CHECK(!uut.write_finalize());
    }
}

TEST_CASE("SlipDecoder") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Create a working buffer for each decoded frame.
    satcat5::io::PacketBufferHeap rx(64);

    // Unit under test writes to this buffer.
    satcat5::io::SlipDecoder uut(&rx);

    SECTION("simple4") {
        uut.write_bytes(5, "\x12\x34\x56\x78\xC0");
        CHECK(rx.get_read_ready() == 4);
        CHECK(rx.read_u8() == 0x12);
        CHECK(rx.read_u8() == 0x34);
        CHECK(rx.read_u8() == 0x56);
        CHECK(rx.read_u8() == 0x78);
        rx.read_finalize();
    }

    SECTION("escape4") {
        uut.write_bytes(7, "\xDB\xDD\x12\xDB\xDC\x34\xC0");
        CHECK(rx.get_read_ready() == 4);
        CHECK(rx.read_u8() == 0xDB);
        CHECK(rx.read_u8() == 0x12);
        CHECK(rx.read_u8() == 0xC0);
        CHECK(rx.read_u8() == 0x34);
        rx.read_finalize();
    }

    SECTION("error-eof-in-escape") {
        log.disable();                      // Suppress error messages
        uut.write_bytes(5, "\xDB\xDD\x12\xDB\xC0");
        CHECK(rx.get_read_ready() == 0);    // Should abort entire frame
        CHECK(!log.empty());                // Confirm error was logged
    }

    SECTION("error-invalid-escape") {
        log.disable();                      // Suppress error messages
        uut.write_bytes(7, "\xDB\xDD\x12\xDB\xCD\x34\xC0");
        CHECK(rx.get_read_ready() == 0);    // Should abort entire frame
        CHECK(!log.empty());                // Confirm error was logged
    }
}

TEST_CASE("SlipCodec") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Unit under test with mock-UART transmit/receive buffers.
    satcat5::io::PacketBufferHeap tx(64), rx(64);
    satcat5::io::SlipCodec uut(&tx, &rx);

    SECTION("Tx") {
        uut.write_u32(0x12345678u);
        uut.write_finalize();
        satcat5::poll::service();
        CHECK(tx.get_read_ready() == 5);
        CHECK(tx.read_u8() == 0x12);
        CHECK(tx.read_u8() == 0x34);
        CHECK(tx.read_u8() == 0x56);
        CHECK(tx.read_u8() == 0x78);
        CHECK(tx.read_u8() == 0xC0);   // EOF
        tx.read_finalize();
    }

    SECTION("Rx") {
        rx.write_bytes(7, "\xDB\xDD\x12\xDB\xDC\x34\xC0");
        rx.write_finalize();
        satcat5::poll::service();
        CHECK(uut.get_read_ready() == 4);
        CHECK(uut.read_u8() == 0xDB);
        CHECK(uut.read_u8() == 0x12);
        CHECK(uut.read_u8() == 0xC0);
        CHECK(uut.read_u8() == 0x34);
        uut.read_finalize();
    }
}
