//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Unit tests for various classes defined in "satcat5/io_core.h"
// Ordinary use is thoroughly covered by other tests; this file is mainly
// reserved for corner cases that are otherwise difficult to reach.

#include <cstring>
#include <hal_test/catch.hpp>
#include <satcat5/build_date.h>
#include <satcat5/io_core.h>
#include <satcat5/utils.h>

namespace io = satcat5::io;

// Bare minimum implementations of Readable and Writeable
class NullRead : public io::Readable {
public:
    unsigned get_read_ready() const {return 0;}
    u8 read_next() {return 0;}
};

class NullWrite : public io::Writeable {
public:
    unsigned get_write_space() const {return 0;}
    void write_next(u8 data) {}
};

class NullRedirect : public io::ReadableRedirect, public io::WriteableRedirect {
public:
    NullRedirect()
        : io::ReadableRedirect(&m_rd)
        , io::WriteableRedirect(&m_wr)
    {}  // Nothing else to initialize

    NullRead m_rd;
    NullWrite m_wr;
};

// Test double-inheritance of ReadableRedirect and WriteableRedirect.
class TestRedirect : public io::ReadableRedirect, public io::WriteableRedirect {
public:
    TestRedirect(io::Readable* src, io::Writeable* dst)
        : io::ReadableRedirect(src)
        , io::WriteableRedirect(dst)
    {}  // Nothing else to initialize
};

TEST_CASE("ArrayRead") {
    const u8 buff[] = {1, 2, 3, 4, 5, 6, 7, 8};
    u8 temp[16];    // Slightly larger
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

    SECTION("underflow_32") {
        CHECK(uut.read_consume(5));
        CHECK(uut.read_u32() == 0);
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
    u8 buff[8];
    io::ArrayWrite uut(buff, sizeof(buff));

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
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 0);
    }

    SECTION("overflow-u16") {
        uut.write_bytes(7, "1234567");
        uut.write_u16(45678u);
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 7);
    }

    SECTION("overflow-u32") {
        uut.write_bytes(5, "12345");
        uut.write_u32(45678u);
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 5);
    }

    SECTION("overflow-u64") {
        uut.write_bytes(3, "123");
        uut.write_u64(45678ull);
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 3);
    }

    SECTION("overflow-u16l") {
        uut.write_bytes(7, "1234567");
        uut.write_u16l(45678u);
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 7);
    }

    SECTION("overflow-u32l") {
        uut.write_bytes(5, "12345");
        uut.write_u32l(45678u);
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 5);
    }

    SECTION("overflow-u64l") {
        uut.write_bytes(3, "123");
        uut.write_u64l(45678u);
        CHECK(uut.write_finalize());
        CHECK(uut.written_len() == 3);
    }

    SECTION("redirect") {
        TestRedirect tmp(0, &uut);
        tmp.write_bytes(3, "123");
        tmp.write_u64(45678ull);
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

TEST_CASE("WriteConversions") {
    u8 buff[32];
    io::ArrayWrite uut(buff, sizeof(buff));

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
}

TEST_CASE("NullIO") {
    SECTION("NullRead") {
        NullRead uut;
        uut.read_finalize();
    }

    SECTION("NullWrite") {
        NullWrite uut;
        uut.write_u64(12345);
        CHECK(uut.write_finalize());
        uut.write_u64(12345);
        uut.write_abort();
    }

    SECTION("NullRedirect") {
        u8 temp[64];
        NullRedirect uut;
        uut.set_callback(0);
        CHECK_FALSE(uut.read_consume(5));           // Should underflow
        CHECK(uut.read_u32() == 0);                 // Should underflow
        CHECK(!uut.read_bytes(sizeof(temp), temp)); // Should underflow
        uut.write_bytes(sizeof(temp), temp);        // No effect
        CHECK(uut.write_finalize());                // Should "succeed"
    }
}

TEST_CASE("LimitedRead") {
    u8 buff[8];

    // Initial setup fills buffer with data.
    io::ArrayWrite wr(buff, sizeof(buff));
    wr.write_u32(0x12345678u);
    wr.write_u32(0x9ABCDEF0u);
    REQUIRE(wr.write_finalize());

    // Create backing Readable object.
    io::ArrayRead rd(buff, wr.written_len());
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
        io::LimitedRead uut(&rd, 5);                // Stop at 5 of 8 bytes
        CHECK_FALSE(uut.read_bytes(8, buff));       // Expect underflow
    }

    SECTION("read_consume") {
        io::LimitedRead uut(&rd, 3);                // Stop at 3 of 8 bytes
        CHECK_FALSE(uut.read_consume(4));           // Expect underflow
    }
}
