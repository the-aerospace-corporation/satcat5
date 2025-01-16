//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Unit tests for various classes defined in "satcat5/io_core.h"
// Ordinary use is thoroughly covered by other tests; this file is mainly
// reserved for corner cases that are otherwise difficult to reach.

#include <cstring>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/build_date.h>
#include <satcat5/io_core.h>
#include <satcat5/utils.h>

namespace io = satcat5::io;

// Test double-inheritance of ReadableRedirect and WriteableRedirect.
class TestRedirect : public io::ReadableRedirect, public io::WriteableRedirect {
public:
    TestRedirect(io::Readable* src, io::Writeable* dst)
        : io::ReadableRedirect(src)
        , io::WriteableRedirect(dst)
    {}  // Nothing else to initialize
};

TEST_CASE("ArrayRead") {
    SATCAT5_TEST_START; // Simulation infrastructure
    const u8 buff[] = {1, 2, 3, 4, 5, 6, 7, 8};
    u8 temp[16];        // Slightly larger buffer
    io::ArrayRead uut(buff, sizeof(buff));

    SECTION("finalize") {
        CHECK(uut.get_read_ready() == 8);
        CHECK(uut.read_consume(3));
        CHECK(uut.get_read_ready() == 5);
        uut.read_finalize();
        CHECK(uut.get_read_ready() == 8);
        CHECK(uut.read_u32() == 0x01020304);
    }

    SECTION("read_reset") {
        CHECK(uut.get_read_ready() == 8);
        CHECK(uut.read_consume(3));
        CHECK(uut.get_read_ready() == 5);
        uut.read_reset(7);
        CHECK(uut.get_read_ready() == 7);
        CHECK(uut.read_u32() == 0x01020304);
    }

    SECTION("redirect") {
        TestRedirect tmp(&uut, 0);
        CHECK(tmp.get_read_ready() == 8);
        CHECK(tmp.read_consume(3));
        CHECK(tmp.get_read_ready() == 5);
        tmp.read_finalize();
        CHECK(tmp.get_read_ready() == 8);
    }

    SECTION("underflow_8") {
        CHECK(uut.read_bytes(8, temp));
        CHECK(uut.read_u8() == 0);
    }

    SECTION("underflow_16") {
        CHECK(uut.read_bytes(7, temp));
        CHECK(uut.read_u16() == 0);
    }

    SECTION("underflow_24") {
        CHECK(uut.read_consume(6));
        CHECK(uut.read_u24() == 0);
    }

    SECTION("underflow_32") {
        CHECK(uut.read_consume(5));
        CHECK(uut.read_u32() == 0);
    }

    SECTION("underflow_48") {
        CHECK(uut.read_consume(3));
        CHECK(uut.read_u48() == 0);
    }

    SECTION("underflow_64") {
        CHECK(uut.read_consume(1));
        CHECK(uut.read_u64() == 0);
    }

    SECTION("underflow_bytes") {
        CHECK(uut.read_consume(5));
        CHECK(!uut.read_bytes(4, temp));
    }

    SECTION("underflow_consume") {
        CHECK(uut.read_consume(5));
        CHECK(!uut.read_consume(4));
    }
}

TEST_CASE("ArrayWrite") {
    SATCAT5_TEST_START; // Simulation infrastructure
    io::ArrayWriteStatic<8> uut;
    const u8* buff = uut.buffer();

    SECTION("abort") {
        uut.write_bytes(5, "12345");
        uut.write_abort();
        CHECK(uut.written_len() == 0);
    }

    SECTION("double-bytes-be") {
        // Confirm output is big-endian IEEE754.
        uut.write_f64(41.123456789);
        CHECK(uut.write_finalize());
        CHECK(buff[0] == 0x40);
        CHECK(buff[1] == 0x44);
        CHECK(buff[2] == 0x8F);
        CHECK(buff[3] == 0xCD);
        CHECK(buff[4] == 0x6E);
        CHECK(buff[5] == 0x9B);
        CHECK(buff[6] == 0x9C);
        CHECK(buff[7] == 0xB2);
    }

    SECTION("double-bytes-le") {
        // Confirm output is little-endian IEEE754.
        uut.write_f64l(41.123456789);
        CHECK(uut.write_finalize());
        CHECK(buff[7] == 0x40);
        CHECK(buff[6] == 0x44);
        CHECK(buff[5] == 0x8F);
        CHECK(buff[4] == 0xCD);
        CHECK(buff[3] == 0x6E);
        CHECK(buff[2] == 0x9B);
        CHECK(buff[1] == 0x9C);
        CHECK(buff[0] == 0xB2);
    }

    SECTION("double-read-be") {
        uut.write_f64(123.456789);
        CHECK(uut.write_finalize());
        io::ArrayRead rd(buff, uut.written_len());
        CHECK(rd.read_f64() == 123.456789);
    }

    SECTION("double-read-le") {
        uut.write_f64l(123.456789);
        CHECK(uut.write_finalize());
        io::ArrayRead rd(buff, uut.written_len());
        CHECK(rd.read_f64l() == 123.456789);
    }

    SECTION("float-bytes-be") {
        // Confirm output is big-endian IEEE754.
        uut.write_f32(5.3f);
        CHECK(uut.write_finalize());
        CHECK(buff[0] == 0x40);
        CHECK(buff[1] == 0xA9);
        CHECK(buff[2] == 0x99);
        CHECK(buff[3] == 0x9A);
    }

    SECTION("float-bytes-le") {
        // Confirm output is little-endian IEEE754.
        uut.write_f32l(5.3f);
        CHECK(uut.write_finalize());
        CHECK(buff[3] == 0x40);
        CHECK(buff[2] == 0xA9);
        CHECK(buff[1] == 0x99);
        CHECK(buff[0] == 0x9A);
    }

    SECTION("float-read-be") {
        uut.write_f32(123.4f);
        CHECK(uut.write_finalize());
        io::ArrayRead rd(buff, uut.written_len());
        CHECK(rd.read_f32() == 123.4f);
    }

    SECTION("float-read-le") {
        uut.write_f32l(123.4f);
        CHECK(uut.write_finalize());
        io::ArrayRead rd(buff, uut.written_len());
        CHECK(rd.read_f32l() == 123.4f);
    }

    SECTION("overflow-bytes") {
        uut.write_bytes(9, "123456789");
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u16") {
        uut.write_bytes(7, "1234567");
        uut.write_u16(45678u);
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u24") {
        uut.write_bytes(6, "123456");
        uut.write_u24(45678u);
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u32") {
        uut.write_bytes(5, "12345");
        uut.write_u32(45678u);
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u48") {
        uut.write_bytes(3, "123");
        uut.write_u48(45678u);
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u64") {
        uut.write_bytes(1, "1");
        uut.write_u64(2345678ull);
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u16l") {
        uut.write_bytes(7, "1234567");
        uut.write_u16l(45678u);
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u24l") {
        uut.write_bytes(6, "123456");
        uut.write_u24l(789u);
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u32l") {
        uut.write_bytes(5, "12345");
        uut.write_u32l(6789u);
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u48l") {
        uut.write_bytes(3, "123");
        uut.write_u48l(45678u);
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u64l") {
        uut.write_bytes(1, "1");
        uut.write_u64l(2345678ull);
        CHECK_FALSE(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("redirect") {
        TestRedirect tmp(0, &uut);
        tmp.write_bytes(3, "123");
        tmp.write_u64(45678ull);
        CHECK_FALSE(tmp.write_finalize());
        CHECK(uut.written_len() == 0);
        tmp.write_bytes(3, "456");
        tmp.write_abort();
        tmp.write_bytes(3, "789");
        CHECK(tmp.write_finalize());
        CHECK(uut.written_len() == 3);
    }

    SECTION("string-read") {
        // Write the word "Test".
        uut.write_str("Test");  // Writes string only.
        uut.write_u8(0);        // Explicit null-termination.
        CHECK(uut.write_finalize());
        REQUIRE(uut.written_len() == 5);
        CHECK(buff[0] == 'T');
        CHECK(buff[1] == 'e');
        CHECK(buff[2] == 's');
        CHECK(buff[3] == 't');
        CHECK(buff[4] == 0);
        // Read the string normally.
        io::ArrayRead rd1(buff, uut.written_len());
        char temp1[8];
        rd1.read_str(sizeof(temp1), temp1);
        CHECK(rd1.get_read_ready() == 0);
        CHECK(temp1 == std::string("Test"));
        // Read into a buffer that's too small.
        // (Should truncate output but still read the entire input.)
        io::ArrayRead rd2(buff, uut.written_len());
        char temp2[4];
        rd2.read_str(sizeof(temp2), temp2);
        CHECK(rd2.get_read_ready() == 0);
        CHECK(temp2 == std::string("Tes"));
    }
}

TEST_CASE("LimitedWrite") {
    SATCAT5_TEST_START; // Simulation infrastructure
    io::ArrayWriteStatic<32> buff;

    SECTION("Limit1") {
        io::LimitedWrite uut(&buff, 1);     // Limit = 1 byte
        CHECK(uut.get_write_space() == 1);
        uut.write_u8(42);                   // Write 1 byte
        CHECK(uut.get_write_space() == 0);
        CHECK(uut.write_finalize());        // Not forwarded
        CHECK(buff.written_len() == 0);
        CHECK(buff.write_finalize());       // Call directly
        CHECK(buff.written_len() == 1);
    }

    SECTION("Limit8") {
        io::LimitedWrite uut(&buff, 8);     // Limit = 8 bytes
        CHECK(uut.get_write_space() == 8);
        uut.write_bytes(7, "1234567");      // Write 7 bytes
        CHECK(uut.get_write_space() == 1);
        CHECK(buff.write_finalize());       // Call directly
        CHECK(buff.written_len() == 7);
    }

    SECTION("Limit999") {
        io::LimitedWrite uut(&buff, 999);   // Larger than output!?
        CHECK(uut.get_write_space() == 32); // Whichever comes first
        uut.write_str("Writing 33 bytes should overflow.");
        CHECK(buff.write_finalize());       // Call directly (empty)
        CHECK(buff.written_len() == 0);
    }
}

TEST_CASE("WriteConversions") {
    SATCAT5_TEST_START; // Simulation infrastructure
    io::ArrayWriteStatic<32> uut;
    const u8* buff = uut.buffer();

    SECTION("LittleEndian") {
        uut.write_s16l(12345);
        uut.write_s32l(1234567890);
        uut.write_s64l(1234567890123456789ll);
        uut.write_u16l(12345);
        uut.write_u32l(1234567890);
        uut.write_u64l(1234567890123456789ll);
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 28);

        io::ArrayRead rd(buff, uut.written_len());
        CHECK(rd.read_s16l() == 12345);
        CHECK(rd.read_s32l() == 1234567890);
        CHECK(rd.read_s64l() == 1234567890123456789ll);
        CHECK(rd.read_u16l() == 12345);
        CHECK(rd.read_u32l() == 1234567890);
        CHECK(rd.read_u64l() == 1234567890123456789ll);
    }

    SECTION("SignedInts") {
        uut.write_s8(-123);
        uut.write_s8(+123);
        uut.write_s16(-12345);
        uut.write_s16(+12345);
        uut.write_s32(-1234567890);
        uut.write_s32(+1234567890);
        uut.write_s64(-1234567890123456789ll);
        uut.write_s64(+1234567890123456789ll);
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 30);

        io::ArrayRead rd(buff, uut.written_len());
        CHECK(rd.read_s8() == -123);
        CHECK(rd.read_s8() == +123);
        CHECK(rd.read_s16() == -12345);
        CHECK(rd.read_s16() == +12345);
        CHECK(rd.read_s32() == -1234567890);
        CHECK(rd.read_s32() == +1234567890);
        CHECK(rd.read_s64() == -1234567890123456789ll);
        CHECK(rd.read_s64() == +1234567890123456789ll);
    }

    SECTION("OddSizes") {
        uut.write_u24 (12345678);
        uut.write_u24l(12345678);
        uut.write_s24 (-1234567);
        uut.write_s24l(-1234567);
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 12);

        io::ArrayRead rd1(buff, uut.written_len());
        CHECK(rd1.read_u24()  == 12345678);
        CHECK(rd1.read_u24l() == 12345678);
        CHECK(rd1.read_s24()  == -1234567);
        CHECK(rd1.read_s24l() == -1234567);

        uut.write_u48 (123456789012345ll);
        uut.write_u48l(123456789012345ll);
        uut.write_s48 (-123456789012345ll);
        uut.write_s48l(-123456789012345ll);
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 24);

        io::ArrayRead rd2(buff, uut.written_len());
        CHECK(rd2.read_u48()  == 123456789012345ll);
        CHECK(rd2.read_u48l() == 123456789012345ll);
        CHECK(rd2.read_s48()  == -123456789012345ll);
        CHECK(rd2.read_s48l() == -123456789012345ll);
    }
}

TEST_CASE("NullIO") {
    SATCAT5_TEST_START; // Simulation infrastructure

    SECTION("NullRead") {
        CHECK(io::null_read.get_read_ready() == 0);
        io::null_read.read_finalize();
    }

    SECTION("NullSink") {
        satcat5::test::RandomSource src(256);
        src.set_callback(&io::null_sink);
        src.notify();
    }

    SECTION("NullWrite0") {
        io::NullWrite uut(0);               // Do not accept writes
        uut.write_u64(12345);               // Should overflow
        CHECK(uut.write_finalize());        // Overflows are not tracked
        uut.write_u64(12345);               // Should overflow
        uut.write_abort();                  // Should succeed
    }

    SECTION("NullWrite1") {
        io::NullWrite uut(1024);            // Accept writes
        uut.write_u64(12345);               // Accept and discard
        CHECK(uut.write_finalize());        // Should "succeed"
        uut.write_u64(12345);               // Accept and discard
        uut.write_abort();                  // Should succeed
    }

    SECTION("NullRedirect") {
        u8 temp[64];
        TestRedirect uut(&io::null_read, &io::null_write);
        uut.set_callback(0);
        CHECK_FALSE(uut.read_consume(5));           // Should underflow
        CHECK(uut.read_u32() == 0);                 // Should underflow
        CHECK(!uut.read_bytes(sizeof(temp), temp)); // Should underflow
        CHECK(uut.get_write_space() > 0);           // Default accepts writes
        uut.write_bytes(sizeof(temp), temp);        // No effect
        CHECK(uut.write_finalize());                // Should "succeed"
    }
}

TEST_CASE("LimitedRead") {
    SATCAT5_TEST_START; // Simulation infrastructure

    // Initial setup fills buffer with data.
    io::ArrayWriteStatic<8> wr;
    wr.write_u32(0x12345678u);
    wr.write_u32(0x9ABCDEF0u);
    REQUIRE(wr.write_finalize());

    // Create backing Readable object.
    io::ArrayRead rd(wr.buffer(), wr.written_len());
    REQUIRE(rd.get_read_ready() == 8);              // Initial state

    SECTION("read_normal") {
        io::LimitedRead uut(&rd, 4);                // Stop at 4 of 8 bytes
        CHECK(uut.get_read_ready() == 4);
        CHECK(uut.read_u16() == 0x1234);
        CHECK(uut.get_read_ready() == 2);
        CHECK(uut.read_u16() == 0x5678);
        CHECK(uut.get_read_ready() == 0);           // Now "empty"
        CHECK(rd.get_read_ready() == 4);            // Still has 4 left
    }

    SECTION("read_bytes") {
        u8 temp[8];
        io::LimitedRead uut(&rd, 5);                // Stop at 5 of 8 bytes
        CHECK_FALSE(uut.read_bytes(8, temp));       // Expect underflow
    }

    SECTION("read_consume") {
        io::LimitedRead uut(&rd, 3);                // Stop at 3 of 8 bytes
        CHECK_FALSE(uut.read_consume(4));           // Expect underflow
    }

    SECTION("too_long") {
        io::LimitedRead uut(&rd, 10);               // Limit exceeds input
        CHECK(uut.get_read_ready() == 8);           // Should stop early
    }
}
