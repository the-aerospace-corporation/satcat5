//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for misc math utilities.

#include <cmath>
#include <cstring>
#include <hal_posix/file_io.h>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/build_date.h>
#include <satcat5/list.h>
#include <satcat5/utils.h>
#include <set>

using namespace satcat5::util;
using satcat5::test::Statistics;

TEST_CASE("build_date.h") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Get the two build-date macros.
    u32 build_code = satcat5::get_sw_build_code();
    const char* build_str = satcat5::get_sw_build_string();
    printf("Build date 0x%08X = %s\n", build_code, build_str);
    CHECK(strlen(build_str) == 19);
}

TEST_CASE("file_io.h") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    const char* TEST_FILE = "simulations/test_file_io.dat";

    SECTION("write") {
        // Create a short test file.
        satcat5::io::FileWriter uut(TEST_FILE);
        CHECK(uut.get_write_space() >= 4);
        uut.write_u32(0xDEADBEEF);
        uut.write_abort();
        uut.write_u32(0x12345678);
        CHECK(uut.write_finalize());
    }

    SECTION("read") {
        // Read the test file we just created.
        satcat5::io::FileReader uut(TEST_FILE);
        CHECK(uut.get_read_ready() == 4);
        CHECK(uut.read_u32() == 0x12345678);
        uut.read_finalize();
    }
}

TEST_CASE("posix_utils.h") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    SECTION("log-format") {
        const satcat5::eth::MacAddr TEST_MAC
            = {0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01};
        const satcat5::ip::Addr TEST_IP(192, 168, 0, 1);
        CHECK(satcat5::log::format(TEST_MAC) == "DE:AD:BE:EF:00:01");
        CHECK(satcat5::log::format(TEST_IP) == "192.168.0.1");
    }
}

TEST_CASE("test_infastructure") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Confirm full-scale output range of the Catch2 PRNG.
    SECTION("SimplePcg32") {
        Catch::SimplePcg32 rng;
        u32 rmin = rng(), rmax = rng();
        for (unsigned a = 0 ; a < 100000 ; ++a) {
            u32 tmp = rng();
            if (tmp < rmin) rmin = tmp;
            if (tmp > rmax) rmax = tmp;
        }
        CHECK(rmin < 0x00100000u);
        CHECK(rmax > 0xFFF00000u);
    }
}

TEST_CASE("utils.h") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    SECTION("mask8v") {
        volatile u8 tmp;
        tmp = 0x11;     set_mask_u8(tmp, 0x0F);             CHECK(tmp == 0x1F);
        tmp = 0x22;     set_mask_u8(tmp, 0x0F);             CHECK(tmp == 0x2F);
        tmp = 0x33;     clr_mask_u8(tmp, 0x0F);             CHECK(tmp == 0x30);
        tmp = 0x44;     clr_mask_u8(tmp, 0x0F);             CHECK(tmp == 0x40);
    }
    SECTION("mask8") {
        u8 tmp;
        tmp = 0x11;     set_mask_u8(tmp, 0x0F);             CHECK(tmp == 0x1F);
        tmp = 0x22;     set_mask_u8(tmp, 0x0F);             CHECK(tmp == 0x2F);
        tmp = 0x33;     clr_mask_u8(tmp, 0x0F);             CHECK(tmp == 0x30);
        tmp = 0x44;     clr_mask_u8(tmp, 0x0F);             CHECK(tmp == 0x40);
        tmp = 0x55;     set_mask_if<u8>(tmp, 0x0F, 0);      CHECK(tmp == 0x50);
        tmp = 0x66;     set_mask_if<u8>(tmp, 0x0F, 1);      CHECK(tmp == 0x6F);
    }
    SECTION("mask16") {
        u16 tmp;
        tmp = 0x1111;   set_mask_u16(tmp, 0x0F0F);          CHECK(tmp == 0x1F1F);
        tmp = 0x2222;   set_mask_u16(tmp, 0x0F0F);          CHECK(tmp == 0x2F2F);
        tmp = 0x3333;   clr_mask_u16(tmp, 0x0F0F);          CHECK(tmp == 0x3030);
        tmp = 0x4444;   clr_mask_u16(tmp, 0x0F0F);          CHECK(tmp == 0x4040);
        tmp = 0x5555;   set_mask_if<u16>(tmp, 0x0F0F, 0);   CHECK(tmp == 0x5050);
        tmp = 0x6666;   set_mask_if<u16>(tmp, 0x0F0F, 1);   CHECK(tmp == 0x6F6F);
    }
    SECTION("mask32") {
        u32 tmp;
        tmp = 0x1111;   set_mask_u32(tmp, 0x0F0F);          CHECK(tmp == 0x1F1F);
        tmp = 0x2222;   set_mask_u32(tmp, 0x0F0F);          CHECK(tmp == 0x2F2F);
        tmp = 0x3333;   clr_mask_u32(tmp, 0x0F0F);          CHECK(tmp == 0x3030);
        tmp = 0x4444;   clr_mask_u32(tmp, 0x0F0F);          CHECK(tmp == 0x4040);
        tmp = 0x5555;   set_mask_if<u32>(tmp, 0x0F0F, 0);   CHECK(tmp == 0x5050);
        tmp = 0x6666;   set_mask_if<u32>(tmp, 0x0F0F, 1);   CHECK(tmp == 0x6F6F);
    }
    SECTION("mask64") {
        u64 tmp;
        tmp = 0x1111;   set_mask<u64>(tmp, 0x0F0F);         CHECK(tmp == 0x1F1F);
        tmp = 0x2222;   set_mask<u64>(tmp, 0x0F0F);         CHECK(tmp == 0x2F2F);
        tmp = 0x3333;   clr_mask<u64>(tmp, 0x0F0F);         CHECK(tmp == 0x3030);
        tmp = 0x4444;   clr_mask<u64>(tmp, 0x0F0F);         CHECK(tmp == 0x4040);
        tmp = 0x5555;   set_mask_if<u64>(tmp, 0x0F0F, 0);   CHECK(tmp == 0x5050);
        tmp = 0x6666;   set_mask_if<u64>(tmp, 0x0F0F, 1);   CHECK(tmp == 0x6F6F);
    }
    SECTION("mask_lower") {
        CHECK(mask_lower<u8>(0) == 0x00);
        CHECK(mask_lower<u8>(1) == 0x01);
        CHECK(mask_lower<u8>(2) == 0x03);
        CHECK(mask_lower<u8>(3) == 0x07);
        CHECK(mask_lower<u8>(4) == 0x0F);
        CHECK(mask_lower<u8>(5) == 0x1F);
        CHECK(mask_lower<u8>(6) == 0x3F);
        CHECK(mask_lower<u8>(7) == 0x7F);
        CHECK(mask_lower<u8>(8) == 0xFF);
        CHECK(mask_lower<u64>(0) == 0ull);
        CHECK(mask_lower<u64>(1) == 1ull);
        CHECK(mask_lower<u64>(64) == ~0ull);
    }
    SECTION("optional") {
        optional<s8> opt1;
        CHECK_FALSE(opt1.has_value());
        CHECK(opt1.value_or(-1) == -1);
        opt1 = 1;
        CHECK(opt1.has_value());
        CHECK(opt1.value() == 1);
        CHECK(opt1.value_or(-1) == 1);
        optional<s8> opt2(2);
        CHECK(opt2.has_value());
        CHECK(opt2.value() == 2);
        CHECK(opt2);
        opt2.reset();
        CHECK_FALSE(opt2.has_value());
        CHECK(!opt2);
    }
    SECTION("max3") {
        // Three-argument maximum.
        CHECK(max_u32(1, 2, 3) == 3);
        CHECK(max_u32(1, 3, 2) == 3);
        CHECK(max_u32(2, 1, 3) == 3);
        CHECK(max_u32(2, 3, 1) == 3);
        CHECK(max_u32(3, 1, 2) == 3);
        CHECK(max_u32(3, 2, 1) == 3);
    }
    SECTION("is_multiple") {
        // Check if A is a multiple of B.
        CHECK(is_multiple_u32(42*1, 42));
        CHECK(is_multiple_u32(42*2, 42));
        CHECK(is_multiple_u32(42*3, 42));
        CHECK(!is_multiple_u32(42*1-1, 42));
        CHECK(!is_multiple_u32(42*2-1, 42));
        CHECK(!is_multiple_u32(42*3-1, 42));
        CHECK(!is_multiple_u32(42*1+1, 42));
        CHECK(!is_multiple_u32(42*2+1, 42));
        CHECK(!is_multiple_u32(42*3+1, 42));
    }
    SECTION("divide") {
        // Signed modulo/divide functions.
        CHECK(modulo<s32>(-7, 4) ==  1);
        CHECK(modulo<s32>(-6, 4) ==  2);
        CHECK(modulo<s32>(-5, 4) ==  3);
        CHECK(modulo<s32>(-4, 4) ==  0);
        CHECK(divide<s32>(-7, 4) == -2);
        CHECK(divide<s32>(-6, 4) == -2);
        CHECK(divide<s32>(-5, 4) == -2);
        CHECK(divide<s32>(-4, 4) == -1);
        // 7 div 3 = 2.333...
        CHECK(div_floor_u32(7, 3) == 2);
        CHECK(div_floor_s32(7, 3) == 2);
        CHECK(div_round_u32(7, 3) == 2);
        CHECK(div_round_s32(7, 3) == 2);
        CHECK(div_ceil_u32 (7, 3) == 3);
        CHECK(div_ceil_s32 (7, 3) == 3);
        // 8 div 3 = 2.667...
        CHECK(div_floor_u32(8, 3) == 2);
        CHECK(div_floor_s32(8, 3) == 2);
        CHECK(div_round_u32(8, 3) == 3);
        CHECK(div_round_s32(8, 3) == 3);
        CHECK(div_ceil_u32 (8, 3) == 3);
        CHECK(div_ceil_s32 (8, 3) == 3);
        // 9 div 3 = 3.000
        CHECK(div_floor_u32(9, 3) == 3);
        CHECK(div_floor_s32(9, 3) == 3);
        CHECK(div_round_u32(9, 3) == 3);
        CHECK(div_round_s32(9, 3) == 3);
        CHECK(div_ceil_u32 (9, 3) == 3);
        CHECK(div_ceil_s32 (9, 3) == 3);
    }
    SECTION("log2") {
        // log2(x), rounded up or down
        CHECK(log2_ceil<u32>(1) == 0);
        CHECK(log2_ceil<u32>(2) == 1);
        CHECK(log2_ceil<u32>(3) == 2);
        CHECK(log2_ceil<u32>(4) == 2);
        CHECK(log2_ceil<u32>(5) == 3);
        CHECK(log2_ceil<u32>(6) == 3);
        CHECK(log2_ceil<u32>(7) == 3);
        CHECK(log2_ceil<u32>(8) == 3);
        CHECK(log2_floor<u32>(1) == 0);
        CHECK(log2_floor<u32>(2) == 1);
        CHECK(log2_floor<u32>(3) == 1);
        CHECK(log2_floor<u32>(4) == 2);
        CHECK(log2_floor<u32>(5) == 2);
        CHECK(log2_floor<u32>(6) == 2);
        CHECK(log2_floor<u32>(7) == 2);
        CHECK(log2_floor<u32>(8) == 3);
    }
    SECTION("round") {
        // Rounding for signed doubles.
        CHECK(round_s64(-1.51) == -2);
        CHECK(round_s64(-1.49) == -1);
        CHECK(round_s64(-0.51) == -1);
        CHECK(round_s64(-0.49) == 0);
        CHECK(round_s64( 0.49) == 0);
        CHECK(round_s64( 0.51) == 1);
        CHECK(round_s64( 1.49) == 1);
        CHECK(round_s64( 1.51) == 2);
        // Rounding for signed floats.
        CHECK(round_s64(-1.51f) == -2);
        CHECK(round_s64(-1.49f) == -1);
        CHECK(round_s64(-0.51f) == -1);
        CHECK(round_s64(-0.49f) == 0);
        CHECK(round_s64( 0.49f) == 0);
        CHECK(round_s64( 0.51f) == 1);
        CHECK(round_s64( 1.49f) == 1);
        CHECK(round_s64( 1.51f) == 2);
        // Rounding for unsigned doubles.
        CHECK(round_u64( 0.01) == 0);
        CHECK(round_u64( 0.49) == 0);
        CHECK(round_u64( 0.51) == 1);
        CHECK(round_u64( 1.49) == 1);
        CHECK(round_u64( 1.51) == 2);
        // Rounding for unsigned floats.
        CHECK(round_u64( 0.01f) == 0);
        CHECK(round_u64( 0.49f) == 0);
        CHECK(round_u64( 0.51f) == 1);
        CHECK(round_u64( 1.49f) == 1);
        CHECK(round_u64( 1.51f) == 2);
    }
    SECTION("saturate-add") {
        CHECK(saturate_add<u8>(1, 126, 128) == 127);
        CHECK(saturate_add<u8>(2, 126, 128) == 128);
        CHECK(saturate_add<u8>(3, 126, 128) == 128);
        CHECK(saturate_add<u8>(4, 250, 255) == 254);
        CHECK(saturate_add<u8>(5, 250, 255) == 255);
        CHECK(saturate_add<u8>(6, 250, 255) == 255);
        CHECK(saturate_add<u8>(4, 250, -1) == 254);
        CHECK(saturate_add<u8>(5, 250, -1) == 255);
        CHECK(saturate_add<u8>(6, 250, -1) == 255);
        CHECK(saturate_add<u8>(4, 250) == 254);
        CHECK(saturate_add<u8>(5, 250) == 255);
        CHECK(saturate_add<u8>(6, 250) == 255);
    }
    SECTION("max") {
        CHECK(max_u8 (3, 5) == 5);
        CHECK(max_u16(3, 5) == 5);
        CHECK(max_u32(3, 5) == 5);
        CHECK(max_u64(3, 5) == 5);
        CHECK(max_s32(3, 5) == 5);
        CHECK(max_s64(3, 5) == 5);
        CHECK(max_u8 (7, 2) == 7);
        CHECK(max_u16(7, 2) == 7);
        CHECK(max_u32(7, 2) == 7);
        CHECK(max_u64(7, 2) == 7);
        CHECK(max_s32(7, 2) == 7);
        CHECK(max_s64(7, 2) == 7);
        CHECK(max_unsigned(3, 5) == 5);
        CHECK(max_unsigned(7, 2) == 7);
    }
    SECTION("min") {
        CHECK(min_u8 (3, 5) == 3);
        CHECK(min_u16(3, 5) == 3);
        CHECK(min_u32(3, 5) == 3);
        CHECK(min_u64(3, 5) == 3);
        CHECK(min_s32(3, 5) == 3);
        CHECK(min_s64(3, 5) == 3);
        CHECK(min_u8 (7, 2) == 2);
        CHECK(min_u16(7, 2) == 2);
        CHECK(min_u32(7, 2) == 2);
        CHECK(min_u64(7, 2) == 2);
        CHECK(min_s32(7, 2) == 2);
        CHECK(min_s64(7, 2) == 2);
        CHECK(min_unsigned(3, 5) == 3);
        CHECK(min_unsigned(7, 2) == 2);
    }
    SECTION("abs") {
        CHECK(abs_s8 (-3) == 3);
        CHECK(abs_s16(-3) == 3);
        CHECK(abs_s32(-3) == 3);
        CHECK(abs_s64(-3) == 3);
        CHECK(abs_s8 (INT8_MIN) == 128u);
        CHECK(abs_s16(INT16_MIN) == 32768u);
        CHECK(abs_s32(INT32_MIN) == 2147483648u);
        CHECK(abs_s64(INT64_MIN) == 9223372036854775808ull);
    }
    SECTION("sign") {
        CHECK(sign<s8>(-3) == -1);
        CHECK(sign<s8>( 0) ==  0);
        CHECK(sign<s8>(+3) == +1);
        CHECK(sign(-3.0) == -1.0);
        CHECK(sign( 0.0) ==  0.0);
        CHECK(sign(+3.0) == +1.0);
    }
    SECTION("square") {
        CHECK(square_u16(3) == 9);
        CHECK(square_s16(3) == 9);
        CHECK(square_u16(65535) == 4294836225u);
        CHECK(square_s16(32767) == 1073676289u);
    }
    SECTION("min_2n") {
        // Given X and Y, find the minimum N such that X * 2^N >= Y.
        const u32 UINT32_HALF = (1u << 31);
        min_2n(0, 5);                   // Don't care, just don't crash
        CHECK(min_2n(5, 4) == 0);       // 5 * 2^0 >= 4
        CHECK(min_2n(5, 5) == 0);       // 5 * 2^0 >= 5
        CHECK(min_2n(5, 6) == 1);       // 5 * 2^1 >= 6
        CHECK(min_2n(5, 11) == 2);      // 5 * 2^2 >= 11
        CHECK(min_2n(1, 2047) == 11);   // 1 * 2^11 >= 2047
        CHECK(min_2n(1, 2048) == 11);   // 1 * 2^11 >= 2048
        CHECK(min_2n(1, 2049) == 12);   // 1 * 2^12 >= 2049
        CHECK(min_2n(1, UINT32_MAX) == 32);
        CHECK(min_2n(UINT32_HALF, UINT32_HALF+1) == 1);
        CHECK(min_2n(UINT32_HALF, UINT32_MAX) == 1);
        CHECK(min_2n(UINT32_HALF/2, UINT32_HALF) == 1);
        CHECK(min_2n(UINT32_HALF/2, UINT32_HALF+1) == 2);
        CHECK(min_2n(UINT32_HALF/2, UINT32_MAX) == 2);
    }
    SECTION("modulo-add") {
        CHECK(modulo_add_u16(1234, 1235) == 1234);
        CHECK(modulo_add_u16(1236, 1235) == 1);
        CHECK(modulo_add_u32(1234, 1235) == 1234);
        CHECK(modulo_add_u32(1236, 1235) == 1);
        CHECK(modulo_add_u64(1234, 1235) == 1234);
        CHECK(modulo_add_u64(1236, 1235) == 1);
        CHECK(modulo_add_uns(1234, 1235) == 1234);
        CHECK(modulo_add_uns(1236, 1235) == 1);
    }
    SECTION("sqrt") {
        // u16
        CHECK(sqrt_u16(49) == 7);
        CHECK(sqrt_u16(63) == 7);
        CHECK(sqrt_u16(64) == 8);
        CHECK(sqrt_u16(65535) == 255u);
        // u32
        CHECK(sqrt_u32(49) == 7);
        CHECK(sqrt_u32(63) == 7);
        CHECK(sqrt_u32(64) == 8);
        CHECK(sqrt_u32((u32)(-1)) == 65535);
        // u64
        CHECK(sqrt_u64(49) == 7);
        CHECK(sqrt_u64(63) == 7);
        CHECK(sqrt_u64(64) == 8);
        CHECK(sqrt_u64((u64)(-1)) == 4294967295u);
    }
    SECTION("be_u16") {
        u8 test[4];
        write_be_u16(test+0, 0x1234u);
        write_be_u16(test+2, 0x5678u);
        CHECK(test[0] == 0x12u);
        CHECK(test[1] == 0x34u);
        CHECK(test[2] == 0x56u);
        CHECK(test[3] == 0x78u);
        CHECK(extract_be_u32(test) == 0x12345678u);
        CHECK(extract_be_u16(test+0) == 0x1234u);
        CHECK(extract_be_u16(test+2) == 0x5678u);
    }
    SECTION("be_u32") {
        u8 test[4];
        write_be_u32(test, 0x12345678u);
        CHECK(test[0] == 0x12u);
        CHECK(test[1] == 0x34u);
        CHECK(test[2] == 0x56u);
        CHECK(test[3] == 0x78u);
        CHECK(extract_be_u32(test) == 0x12345678u);
        CHECK(extract_be_u16(test+0) == 0x1234u);
        CHECK(extract_be_u16(test+2) == 0x5678u);
    }
    SECTION("be_u64") {
        u8 test[8];
        write_be_u64(test, 0x123456789ABCDEF0ull);
        CHECK(test[0] == 0x12u);
        CHECK(test[1] == 0x34u);
        CHECK(test[2] == 0x56u);
        CHECK(test[3] == 0x78u);
        CHECK(test[4] == 0x9Au);
        CHECK(test[5] == 0xBCu);
        CHECK(test[6] == 0xDEu);
        CHECK(test[7] == 0xF0u);
        CHECK(extract_be_u64(test) == 0x123456789ABCDEF0ull);
        CHECK(extract_be_u32(test+0) == 0x12345678u);
        CHECK(extract_be_u32(test+4) == 0x9ABCDEF0u);
    }
    SECTION("popcount") {
        CHECK(popcount(0x00000000u) == 0);
        CHECK(popcount(0x00000001u) == 1);
        CHECK(popcount(0x01234567u) == 12);
        CHECK(popcount(0x89ABCDEFu) == 20);
        CHECK(popcount(0xFFFFFFFFu) == 32);
    }
    SECTION("reverse_bytes") {
        CHECK(reverse_bytes_u16(0x1234u) == 0x3412);
        CHECK(reverse_bytes_u32(0x12345678u) == 0x78563412u);
        CHECK(reverse_bytes_u64(0x123456789ABCDEFull) == 0xEFCDAB8967452301ull);
    }
    SECTION("xor_reduce") {
        CHECK(!xor_reduce_u8(0x12));        // 2 set bits
        CHECK(xor_reduce_u8(0x34));         // 3 set bits
        CHECK(xor_reduce_u16(0x1234));      // 5 set bits
        CHECK(!xor_reduce_u16(0x2345));     // 6 set bits
        CHECK(xor_reduce_u32(0x123456));    // 9 set bits
        CHECK(!xor_reduce_u32(0x1234567));  // 12 set bits
        CHECK(xor_reduce_u64(0x123456789ABCDull));      // 25 set bits
        CHECK(!xor_reduce_u64(0x123456789ABCDEull));    // 28 set bits
    }
    SECTION("Prng") {
        // Confirm no repeats in the first N outputs.
        std::set<u32> history;
        Prng uut;
        unsigned count_repeat = 0;
        for (unsigned a = 0 ; a < 10000 ; ++a) {
            u32 next = uut.next();  // Full range = [0..2^32)
            if (history.find(next) != history.end()) ++count_repeat;
        }
        // CHECK at the end to reduce Catch2 verbosity in debug mode.
        CHECK(count_repeat == 0);
        // Histogram over a smaller range.
        constexpr u32 TEST_MIN = 123, TEST_MAX = 129, TEST_COUNT = 10000;
        std::vector<unsigned> histo(1 + TEST_MAX - TEST_MIN, 0);
        u32 test_min = UINT32_MAX, test_max = 0;
        for (unsigned a = 0 ; a < TEST_COUNT ; ++a) {
            u32 next = uut.next(TEST_MIN, TEST_MAX);
            if (next < test_min) test_min = next;
            if (next > test_max) test_max = next;
            if (TEST_MIN <= next && next <= TEST_MAX)
                ++histo[next - TEST_MIN];
        }
        // Sweep over the histogram counts.
        u32 histo_min = histo[0], histo_max = histo[0];
        for (unsigned a = 1 ; a < histo.size() ; ++a) {
            if (histo[a] < histo_min) histo_min = histo[a];
            if (histo[a] > histo_max) histo_max = histo[a];
        }
        // CHECK at the end to reduce Catch2 verbosity in debug mode.
        CHECK(test_min == TEST_MIN);    // Match expected span exactly
        CHECK(test_max == TEST_MAX);
        CHECK(histo_min >= 1314);       // Equal = 1428 +/- 38 (1 sigma)
        CHECK(histo_max <= 1542);       // --> Threshold = 3 sigma
    }
    SECTION("RunningMax") {
        RunningMax uut;                 // Max = "None"
        CHECK(uut.m_label[0] == 'N');
        CHECK(uut.m_maximum == 0);
        uut.update("A", 5);             // New max = "A"
        CHECK(uut.m_label[0] == 'A');
        CHECK(uut.m_maximum == 5);
        uut.update("B", 4);             // No change
        CHECK(uut.m_label[0] == 'A');
        CHECK(uut.m_maximum == 5);
        uut.update("C", 10);            // New max = "C"
        CHECK(uut.m_label[0] == 'C');
        CHECK(uut.m_maximum == 10);
        uut.clear();                    // Max = "None"
        CHECK(uut.m_label[0] == 'N');
        CHECK(uut.m_maximum == 0);
    }
    SECTION("Statistics") {
        Statistics uut;
        uut.add(1.0);
        uut.add(2.0);
        uut.add(3.0);
        uut.add(4.0);
        // Test each function with four data points.
        CHECK(abs(uut.mean() - 2.5) < 1e-9);
        CHECK(abs(uut.msq() - 7.5) < 1e-9);
        CHECK(abs(uut.rms() - sqrt(7.5)) < 1e-9);
        CHECK(abs(uut.std() - sqrt(1.25)) < 1e-9);
        CHECK(abs(uut.var() - 1.25) < 1e-9);
        // Repeat after adding another data point.
        uut.add(5.0);
        CHECK(abs(uut.mean() - 3.0) < 1e-9);
        CHECK(abs(uut.msq() - 11.0) < 1e-9);
        CHECK(abs(uut.rms() - sqrt(11.0)) < 1e-9);
        CHECK(abs(uut.std() - sqrt(2.0)) < 1e-9);
        CHECK(abs(uut.var() - 2.0) < 1e-9);
    }
    SECTION("Endian") {
        const char* lbl = "Unknown";
        if (HOST_BYTE_ORDER() == SATCAT5_LITTLE_ENDIAN)
            lbl = "Little-endian";
        if (HOST_BYTE_ORDER() == SATCAT5_BIG_ENDIAN)
            lbl = "Big-endian";
        printf("Host type = %s\n", lbl);
    }
}
