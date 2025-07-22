//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Unit tests for io::WriteableBroadcast.

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/io_broadcast.h>

TEST_CASE("WriteableBroadcast") {
    SATCAT5_TEST_START;

    // Unit under test: Allocate three slots and assign the first two.
    satcat5::io::WriteableBroadcastStatic<3> uut;
    satcat5::io::PacketBufferHeap out0, out1;
    uut[0] = &out0;
    uut[1] = &out1;

    // Basic message is copied to two outputs.
    SECTION("basic") {
        CHECK(uut.len() == 3);

        CHECK(satcat5::test::write(&uut, "Test message"));
        CHECK(satcat5::test::read(&out0, "Test message"));
        CHECK(satcat5::test::read(&out1, "Test message"));

        uut.write_u16(1234);
        CHECK(uut.write_finalize());
        CHECK(out0.read_u16() == 1234);
        CHECK(out1.read_u16() == 1234);
    }

    // Test the write_abort() method.
    SECTION("abort") {
        uut.write_str("This message will be written, then aborted.");
        uut.write_abort();
        CHECK_FALSE(uut.write_finalize());
        CHECK(out0.get_read_ready() == 0);
        CHECK(out1.get_read_ready() == 0);
    }

    // Test the write_overflow() handler.
    SECTION("overflow") {
         // Set third output with a max length of 8 bytes.
        satcat5::io::ArrayWriteStatic<8> out2;
        uut.port_set(2, &out2);
        // A long message should overflow all three outputs.
        CHECK_FALSE(satcat5::test::write(&uut, "Too long for out2."));
        CHECK(out0.get_read_ready() == 0);
        CHECK(out1.get_read_ready() == 0);
        CHECK(out2.written_len() == 0);
        // Confirm successful flush by writing another message.
        CHECK(satcat5::test::write(&uut, "ShortMsg"));
        CHECK(satcat5::test::read(&out0, "ShortMsg"));
        CHECK(satcat5::test::read(&out1, "ShortMsg"));
        CHECK(out2.written_len() == 8);
    }
}
