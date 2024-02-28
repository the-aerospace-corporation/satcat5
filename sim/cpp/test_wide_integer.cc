//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the wide-integer arithmetic class

#include <hal_posix/posix_utils.h>
#include <hal_test/catch.hpp>
#include <satcat5/io_core.h>
#include <satcat5/utils.h>
#include <satcat5/wide_integer.h>

using namespace satcat5::util;

// Shortcut function for initializing longer constants.
int128_t make128s(u32 a, u32 b, u32 c, u32 d) {
    int128_t tmp;
    tmp.m_data[3] = a; tmp.m_data[2] = b; tmp.m_data[1] = c; tmp.m_data[0] = d;
    return tmp;
}

uint128_t make128u(u32 a, u32 b, u32 c, u32 d) {
    uint128_t tmp;
    tmp.m_data[3] = a; tmp.m_data[2] = b; tmp.m_data[1] = c; tmp.m_data[0] = d;
    return tmp;
}

int256_t make256s(u32 a, u32 b, u32 c, u32 d, u32 e, u32 f, u32 g, u32 h) {
    int256_t tmp;
    tmp.m_data[7] = a; tmp.m_data[6] = b; tmp.m_data[5] = c; tmp.m_data[4] = d;
    tmp.m_data[3] = e; tmp.m_data[2] = f; tmp.m_data[1] = g; tmp.m_data[0] = h;
    return tmp;
}

uint256_t make256u(u32 a, u32 b, u32 c, u32 d, u32 e, u32 f, u32 g, u32 h) {
    uint256_t tmp;
    tmp.m_data[7] = a; tmp.m_data[6] = b; tmp.m_data[5] = c; tmp.m_data[4] = d;
    tmp.m_data[3] = e; tmp.m_data[2] = f; tmp.m_data[1] = g; tmp.m_data[0] = h;
    return tmp;
}

void debug(const uint128_t& x) {
    printf("X = 0x%08X-%08X-%08X-%08X\n", x.m_data[3], x.m_data[2], x.m_data[1], x.m_data[0]);
}

TEST_CASE("wide_integer_signed") {
    Catch::SimplePcg32 rng;

    SECTION("assignment") {
        const int128_t a = int128_t((u32)1234);
        const int128_t b = int128_t((u64)1234);
        int128_t c; c = a;
        int128_t d; d = int128_t((u32)1234);
        CHECK(a == b);
        CHECK(a == c);
        CHECK(a == d);
    }

    SECTION("negatives") {
        const int128_t a = int128_t((s32)1234);
        const int128_t b = int128_t((s64)1234);
        const int128_t c = int128_t((s32)-1234);
        const int128_t d = int128_t((s64)-1234);
        int128_t e; e = int128_t((s32)-1234);
        int128_t f; f = int128_t((s64)-1234);
        CHECK(a == b);
        CHECK(c == d);
        CHECK(c == e);
        CHECK(c == f);
        CHECK(a == -c);
        CHECK(a == -d);
        CHECK(a + c == INT128_ZERO);
        CHECK(a + d == INT128_ZERO);
    }

    SECTION("constants") {
        CHECK(INT128_ZERO.m_data[0] == 0);
        CHECK(INT128_ZERO.m_data[1] == 0);
        CHECK(INT128_ZERO.m_data[2] == 0);
        CHECK(INT128_ZERO.m_data[3] == 0);
        CHECK(INT128_ONE.m_data[0] == 1);
        CHECK(INT128_ONE.m_data[1] == 0);
        CHECK(INT128_ONE.m_data[2] == 0);
        CHECK(INT128_ONE.m_data[3] == 0);
    }

    SECTION("comparison") {
        CHECK      (make128s(1, 2, 3, 4) <  make128s(4, 3, 2, 1));
        CHECK      (make128s(1, 2, 3, 4) <= make128s(4, 3, 2, 1));
        CHECK_FALSE(make128s(1, 2, 3, 4) == make128s(4, 3, 2, 1));
        CHECK      (make128s(1, 2, 3, 4) != make128s(4, 3, 2, 1));
        CHECK_FALSE(make128s(1, 2, 3, 4) >= make128s(4, 3, 2, 1));
        CHECK_FALSE(make128s(1, 2, 3, 4) >  make128s(4, 3, 2, 1));
        CHECK_FALSE(make128s(4, 3, 2, 1) <  make128s(1, 2, 3, 4));
        CHECK_FALSE(make128s(4, 3, 2, 1) <= make128s(1, 2, 3, 4));
        CHECK_FALSE(make128s(4, 3, 2, 1) == make128s(1, 2, 3, 4));
        CHECK      (make128s(4, 3, 2, 1) != make128s(1, 2, 3, 4));
        CHECK      (make128s(4, 3, 2, 1) >= make128s(1, 2, 3, 4));
        CHECK      (make128s(4, 3, 2, 1) >  make128s(1, 2, 3, 4));
        CHECK_FALSE(make128s(5, 5, 5, 5) <  make128s(5, 5, 5, 5));
        CHECK      (make128s(5, 5, 5, 5) <= make128s(5, 5, 5, 5));
        CHECK      (make128s(5, 5, 5, 5) == make128s(5, 5, 5, 5));
        CHECK_FALSE(make128s(5, 5, 5, 5) != make128s(5, 5, 5, 5));
        CHECK      (make128s(5, 5, 5, 5) >= make128s(5, 5, 5, 5));
        CHECK_FALSE(make128s(5, 5, 5, 5) >  make128s(5, 5, 5, 5));
        const int128_t MINUS_ONE(-INT128_ONE);
        CHECK      (MINUS_ONE < INT128_ONE);
        CHECK_FALSE(MINUS_ONE > INT128_ONE);
        CHECK_FALSE(INT128_ONE < MINUS_ONE);
        CHECK      (INT128_ONE > MINUS_ONE);
    }

    SECTION("signed") {
        const int128_t x = make128s(1, 2, 3, 4);
        const int128_t y = -x;
        CHECK_FALSE(x.is_negative());
        CHECK(y.is_negative());
        CHECK(y.abs() == x);
    }

    SECTION("conversion") {
        const int256_t ref = make256s(1, 2, 3, 4, 5, 6, 7, 8);
        CHECK(bool(ref));           // Boolean (x != 0)
        CHECK(int32_t(ref) == 8);   // Convert to s32 / s64
        CHECK(int64_t(ref) == 0x700000008ll);
        CHECK(uint32_t(ref) == 8);  // Convert to u32 / u64
        CHECK(uint64_t(ref) == 0x700000008ull);
        const int128_t uut1(ref);   // Truncate
        for (unsigned a = 0 ; a < 4 ; ++a) CHECK(uut1.m_data[a] == ref.m_data[a]);
        const int512_t uut2(ref);   // Zero-pad
        for (unsigned a = 0 ; a < 8 ; ++a) CHECK(uut2.m_data[a] == ref.m_data[a]);
        for (unsigned a = 8 ; a < 16 ; ++a) CHECK(uut2.m_data[a] == 0);
        const int512_t uut3(-ref);  // Sign-extend
        CHECK(uut3.m_data[0] == 0xFFFFFFF8u);
        CHECK(uut3.m_data[1] == 0xFFFFFFF8u);
        CHECK(uut3.m_data[2] == 0xFFFFFFF9u);
        CHECK(uut3.m_data[3] == 0xFFFFFFFAu);
        CHECK(uut3.m_data[4] == 0xFFFFFFFBu);
        CHECK(uut3.m_data[5] == 0xFFFFFFFCu);
        CHECK(uut3.m_data[6] == 0xFFFFFFFDu);
        CHECK(uut3.m_data[7] == 0xFFFFFFFEu);
        CHECK(uut3.m_data[8] == 0xFFFFFFFFu);
        CHECK(uut3.m_data[9] == 0xFFFFFFFFu);
        CHECK(uut3.m_data[10] == 0xFFFFFFFFu);
        CHECK(uut3.m_data[11] == 0xFFFFFFFFu);
        CHECK(uut3.m_data[12] == 0xFFFFFFFFu);
        CHECK(uut3.m_data[13] == 0xFFFFFFFFu);
        CHECK(uut3.m_data[14] == 0xFFFFFFFFu);
        CHECK(uut3.m_data[15] == 0xFFFFFFFFu);
    }

    SECTION("msb") {
        CHECK(make128s(0, 0, 0, 0).msb() == 0);
        CHECK(make128s(0, 0, 0, 15).msb() == 3);
        CHECK(make128s(0, 0, 0, 16).msb() == 4);
        CHECK(make128s(0, 0, 0, 17).msb() == 4);
        CHECK(make128s(0, 0, 0, UINT32_MAX).msb() == 31);
        CHECK(make128s(0, 0, 38, 5).msb() == 37);
        CHECK(make128s(0, 9, 99, 3).msb() == 67);
        CHECK(make128s(1, 7, 42, 8).msb() == 96);
        CHECK(make128s(UINT32_MAX, 0, 0, 0).msb() == 127);
    }

    SECTION("increment") {
        // Pre-increment/decrement
        CHECK(++make128s(0, 0, 0, 0) == make128s(0, 0, 0, 1));
        CHECK(++make128s(1, 2, 3, UINT32_MAX) == make128s(1, 2, 4, 0));
        CHECK(++make128s(UINT32_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX) == make128s(0, 0, 0, 0));
        CHECK(--make128s(0, 0, 0, 7) == make128s(0, 0, 0, 6));
        CHECK(--make128s(0, 0, 0, 0) == make128s(UINT32_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX));
        // Post-increment/decrement
        int128_t uut1 = make128s(1, 2, 3, 4);
        CHECK(uut1++ == make128s(1, 2, 3, 4));
        CHECK(uut1++ == make128s(1, 2, 3, 5));
        CHECK(uut1-- == make128s(1, 2, 3, 6));
        CHECK(uut1-- == make128s(1, 2, 3, 5));
    }

    SECTION("addition") {
        const int128_t a = make128s(1, 2, 3, 4) + make128s(5, 6, 7, 8);
        CHECK(a == make128s(6, 8, 10, 12));
        const int128_t b = make128s(0, 0, 0, 1) + make128s(0, 0, 0, 0xFFFFFFFFu);
        CHECK(b == make128s(0, 0, 1, 0));
        const int128_t c = make128s(1, 2, 0xFFFFFFFFu, 3) + make128s(4, 5, 0xFFFFFFFFu, 6);
        CHECK(c == make128s(5, 8, 0xFFFFFFFEu, 9));
        int128_t d = make128s(1, 2, 3, 4); d += make128s(5, 6, 7, 8);
        CHECK(d == make128s(6, 8, 10, 12));
        int128_t e = make128s(0, 0, 0, 1); e += make128s(0, 0, 0, 0xFFFFFFFFu);
        CHECK(e == make128s(0, 0, 1, 0));
        int128_t f = make128s(1, 2, 0xFFFFFFFFu, 3); f += make128s(4, 5, 0xFFFFFFFFu, 6);
        CHECK(f == make128s(5, 8, 0xFFFFFFFEu, 9));
        const int128_t g = make128s(1, 2, 0xFFFFFFFFu, 0xFFFFFFFFu) + make128s(3, 4, 0xFFFFFFFFu, 5);
        CHECK(g == make128s(4, 7, 0xFFFFFFFFu, 4));
        int128_t h = make128s(1, 2, 0xFFFFFFFFu, 0xFFFFFFFFu); h += make128s(3, 4, 0xFFFFFFFFu, 5);
        CHECK(h == make128s(4, 7, 0xFFFFFFFFu, 4));
    }

    SECTION("addition3") {
        // Define three constants and their sum.
        const int128_t a((s64)-985604758632441288ll);
        const int128_t b((s64)1007229118000000000ll);
        const int128_t c((s64)104235472715776ll);
        const int128_t isum((s64)21728594840274488ll);
        // Test all permutations of "+" operator.
        // (Addition is commutative, but is our implementation?)
        CHECK(a + b + c == isum);
        CHECK(a + c + b == isum);
        CHECK(b + a + c == isum);
        CHECK(b + c + a == isum);
        CHECK(c + a + b == isum);
        CHECK(c + b + a == isum);
        // Test all permutations of "+=" operator.
        {int128_t x = a; x += b; x += c; CHECK(x == isum);}
        {int128_t x = a; x += c; x += b; CHECK(x == isum);}
        {int128_t x = b; x += a; x += c; CHECK(x == isum);}
        {int128_t x = b; x += c; x += a; CHECK(x == isum);}
        {int128_t x = c; x += a; x += b; CHECK(x == isum);}
        {int128_t x = c; x += b; x += a; CHECK(x == isum);}
    }

    SECTION("subtraction") {
        CHECK(-make128s(0, 0, 0, 0) == make128s(0, 0, 0, 0));
        CHECK(-make128s(0, 0, 0, 1) == make128s(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        CHECK(make128s(5, 6, 7, 8)
            - make128s(1, 2, 3, 4)
           == make128s(4, 4, 4, 4));
        CHECK(make128s(0, 0, 0, 1)
            - make128s(0, 0, 0, 0xFFFFFFFFu)
           == make128s(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 2));
        CHECK(make128s(4, 5, 0xFFFFFFFFu, 6)
            - make128s(1, 2, 0xFFFFFFFFu, 3)
           == make128s(3, 3, 0, 3));
        CHECK(make128s(0, 1, 0x40D931FFu, 0x95EDDB30u)
            - make128s(0, 0, 0x5CB27800u, 0x25849BA1u)
           == make128s(0, 0, 0xE426B9FFu, 0x70693F8Fu));
        int128_t a = make128s(5, 6, 7, 8); a -= make128s(5, 6, 7, 9);
        CHECK(a == make128s(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        int128_t b = make128s(0, 0, 0, 1); b -= make128s(0, 0, 0, 0xFFFFFFFFu);
        CHECK(b == make128s(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 2));
        int128_t c = make128s(4, 5, 0xFFFFFFFFu, 5); c -= make128s(4, 5, 0xFFFFFFFFu, 6);
        CHECK(c == make128s(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
    }

    SECTION("subtract3") {
        // Define three constants and their sum.
        const int128_t a((s64)-985604758632441288ll);
        const int128_t b((s64)1007229118000000000ll);
        const int128_t c((s64)104235472715776ll);
        const int128_t isum((s64)-21728594840274488ll);
        // Test all permutations of "-" operator.
        // (Addition is commutative, but is our implementation?)
        CHECK(-a - b - c == isum);
        CHECK(-a - c - b == isum);
        CHECK(-b - a - c == isum);
        CHECK(-b - c - a == isum);
        CHECK(-c - a - b == isum);
        CHECK(-c - b - a == isum);
        // Test all permutations of "-=" operator.
        {int128_t x = -a; x -= b; x -= c; CHECK(x == isum);}
        {int128_t x = -a; x -= c; x -= b; CHECK(x == isum);}
        {int128_t x = -b; x -= a; x -= c; CHECK(x == isum);}
        {int128_t x = -b; x -= c; x -= a; CHECK(x == isum);}
        {int128_t x = -c; x -= a; x -= b; CHECK(x == isum);}
        {int128_t x = -c; x -= b; x -= a; CHECK(x == isum);}
    }

    SECTION("multiplication") {
        // Note: Division tests also give the multiplier a thorough checkout.
        const int128_t a = make128s(5, 6, 7, 8) * make128s(0, 0, 1, 2);
        CHECK(a == make128s(16, 19, 22, 16));
        int128_t b = make128s(5, 6, 7, 8); b *= make128s(0, 0, 1, 2);
        CHECK(b == make128s(16, 19, 22, 16));
    }

    SECTION("mult_negative") {
        // Multiplication of negative numbers.
        const int128_t a = make128s(5, 6, 7, 8);
        const int128_t b = make128s(0, 0, 0, 3);
        const int128_t c = make128s(0, 0, 4, 9);
        const int128_t ab = a * b;
        const int128_t ac = a * c;
        CHECK(-a *  b == -ab);
        CHECK( a * -b == -ab);
        CHECK(-a * -b ==  ab);
        CHECK(-a *  c == -ac);
        CHECK( a * -c == -ac);
        CHECK(-a * -c ==  ac);
    }

    SECTION("division") {
        // Random cross-checks of multiplication and division.
        for (unsigned a = 0 ; a < 1000 ; ++a) {
            int128_t x, y, d, m;
            x = make128s(rng(), rng(), rng(), rng());
            y = make128s(rng(), rng(), rng(), rng());
            if (y == INT128_ZERO) continue;
            x.divmod(y, d, m);
            if (x != y * d + m) {debug(x); debug(y); debug(d); debug(m);}
            CHECK(d.abs() <= x.abs());
            CHECK(m.abs() <  y.abs());
            CHECK(x == y * d + m);
        }
        // Additional checks for individual operators, in all four quadrants.
        CHECK(int128_t(s32(17)) / int128_t(s32(3)) == int128_t(s32(5)));
        CHECK(int128_t(s32(17)) % int128_t(s32(3)) == int128_t(s32(2)));
        CHECK(int128_t(s32(-17)) / int128_t(s32(3)) == int128_t(s32(-5)));
        CHECK(int128_t(s32(-17)) % int128_t(s32(3)) == int128_t(s32(-2)));
        CHECK(int128_t(s32(17)) / int128_t(s32(-3)) == int128_t(s32(-5)));
        CHECK(int128_t(s32(17)) % int128_t(s32(-3)) == int128_t(s32(2)));
        CHECK(int128_t(s32(-17)) / int128_t(s32(-3)) == int128_t(s32(5)));
        CHECK(int128_t(s32(-17)) % int128_t(s32(-3)) == int128_t(s32(-2)));
        {int128_t a(s32(17));  a /= int128_t(s32(3));  CHECK(a == int128_t(s32(5)));}
        {int128_t a(s32(17));  a %= int128_t(s32(3));  CHECK(a == int128_t(s32(2)));}
        {int128_t a(s32(-17)); a /= int128_t(s32(3));  CHECK(a == int128_t(s32(-5)));}
        {int128_t a(s32(-17)); a %= int128_t(s32(3));  CHECK(a == int128_t(s32(-2)));}
        {int128_t a(s32(17));  a /= int128_t(s32(-3)); CHECK(a == int128_t(s32(-5)));}
        {int128_t a(s32(17));  a %= int128_t(s32(-3)); CHECK(a == int128_t(s32(2)));}
        {int128_t a(s32(-17)); a /= int128_t(s32(-3)); CHECK(a == int128_t(s32(5)));}
        {int128_t a(s32(-17)); a %= int128_t(s32(-3)); CHECK(a == int128_t(s32(-2)));}
    }

    SECTION("fuzzer_add") {
        // Random cross-checks for self-consistency.
        for (unsigned a = 0 ; a < 1000 ; ++a) {
            // Randomize inputs.
            const int128_t x = make128s(rng(), rng(), rng(), rng());
            const int128_t y = make128s(rng(), rng(), rng(), rng());
            // Check that addition and subtraction are self-consistent.
            CHECK((x + y) == (y + x));
            CHECK((x - y) == -(y - x));
            CHECK((x - y) + y == x);
            CHECK((y - x) + x == y);
        }
    }

    SECTION("fuzzer_s64") {
        // Random cross-checks against built-in signed 64-bit arithmetic.
        for (unsigned a = 0 ; a < 1000 ; ++a) {
            // Randomize inputs.
            const s64 x1 = s64(rng()) - s64(rng());
            const s64 y1 = s64(rng()) - s64(rng());
            const int128_t x2(x1);
            const int128_t y2(y1);
            // Check the basic arithmetic operators.
            CHECK(s64(x1 + y1) == s64(x2 + y2));
            CHECK(s64(x1 - y1) == s64(x2 - y2));
            CHECK(s64(x1 * y1) == s64(x2 * y2));
            CHECK(s64(x1 | y1) == s64(x2 | y2));
            CHECK(s64(x1 & y1) == s64(x2 & y2));
            CHECK(s64(x1 ^ y1) == s64(x2 ^ y2));
            CHECK(s64(x1 >> 8u) == s64(x2 >> 8u));
            // Check handling of negative numbers.
            CHECK(abs_s64(x1) == u64(x2.abs()));
            CHECK(abs_s64(y1) == u64(y2.abs()));
            CHECK((x1 < 0) == x2.is_negative());
            CHECK((y1 < 0) == y2.is_negative());
        }
    }

    SECTION("bitshift") {
        const int128_t MAX_POS = make128s(0x7FFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu);
        const int128_t MAX_NEG = make128s(0x80000000u, 0, 0, 0);
        CHECK(make128s(1, 2, 3, 4) << 0u == make128s(1, 2, 3, 4));
        CHECK(make128s(1, 2, 3, 4) >> 0u == make128s(1, 2, 3, 4));
        CHECK(make128s(1, 2, 3, 4) << 32u == make128s(2, 3, 4, 0));
        CHECK(make128s(1, 2, 3, 4) >> 32u == make128s(0, 1, 2, 3));
        CHECK(make128s(0, 0, 0, 1) << 37u == make128s(0, 0, 32, 0));
        CHECK(make128s(0, 0, 32, 0) >> 37u == make128s(0, 0, 0, 1));
        CHECK(make128s(0, 0, 0, 1) << 127u == make128s(0x80000000u, 0, 0, 0));
        CHECK(MAX_POS >> 0u == MAX_POS);
        CHECK(MAX_POS >> 1u == make128s(0x3FFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        CHECK(MAX_POS >> 32u == make128s(0, 0x7FFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        CHECK(MAX_POS >> 37u == make128s(0, 0x03FFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        CHECK(MAX_POS >> 126u == INT128_ONE);
        CHECK(MAX_NEG >> 0u == MAX_NEG);
        CHECK(MAX_NEG >> 1u == make128s(0xC0000000u, 0, 0, 0));
        CHECK(MAX_NEG >> 32u == make128s(0xFFFFFFFFu, 0x80000000u, 0, 0));
        CHECK(MAX_NEG >> 37u == make128s(0xFFFFFFFFu, 0xFC000000, 0, 0));
        CHECK(MAX_NEG >> 127u == -INT128_ONE);
        int128_t a = make128s(0, 0, 0xFFFFFFFFu, 0);
        a <<= 3u; CHECK(a == make128s(0, 0x07, 0xFFFFFFF8u, 0));
        a >>= 6u; CHECK(a == make128s(0, 0, 0x1FFFFFFFu, 0xE0000000u));
    }

    SECTION("bitwise") {
        int128_t a = make128s(1, 2, 3, 4);
        CHECK((a | make128s(4, 3, 2, 1)) == make128s(5, 3, 3, 5));
        CHECK((a ^ make128s(4, 3, 2, 1)) == make128s(5, 1, 1, 5));
        CHECK((a & make128s(4, 3, 2, 1)) == make128s(0, 2, 2, 0));
        a |= make128s(0, 0, 0, 1); CHECK(a == make128s(1, 2, 3, 5));
        a ^= make128s(0, 0, 1, 0); CHECK(a == make128s(1, 2, 2, 5));
        a &= make128s(1, 1, 1, 1); CHECK(a == make128s(1, 0, 0, 1));
    }

    SECTION("logging") {
        satcat5::log::ToConsole logger;
        logger.disable();   // Don't echo to screen.
        const int128_t a = make128s(1, 2, 3, 4);
        satcat5::log::Log(satcat5::log::INFO, "Test").write_obj(a);
        CHECK(logger.contains("0x00000001000000020000000300000004"));
    }

    SECTION("read-write") {
        u8 buff[64];
        satcat5::io::ArrayWrite uut(buff, sizeof(buff));
        const int128_t a = make128s(1, 2, 3, 4);
        const int256_t b = make256s(1, 2, 3, 4, 5, 6, 7, 8);

        uut.write_obj(a);
        uut.write_obj(b);
        uut.write_finalize();
        CHECK(uut.written_len() == 48);

        int128_t c;
        int256_t d, e;
        satcat5::io::ArrayRead rd(buff, uut.written_len());
        CHECK(rd.read_obj(c));          // Should succeed
        CHECK(rd.read_obj(d));          // Should succeed
        CHECK_FALSE(rd.read_obj(e));    // Intentional underflow
        CHECK(a == c);
        CHECK(b == d);
    }
}

TEST_CASE("wide_integer_unsigned") {
    Catch::SimplePcg32 rng;

    SECTION("assignment") {
        const uint128_t a = uint128_t((u32)1234);
        const uint128_t b = uint128_t((u64)1234);
        uint128_t c; c = a;
        uint128_t d; d = uint128_t((u32)1234);
        uint128_t e; e = uint128_t((u64)1234);
        CHECK(a == b);
        CHECK(a == c);
        CHECK(a == d);
        CHECK(a == e);
    }

    SECTION("constants") {
        CHECK(UINT128_ZERO.m_data[0] == 0);
        CHECK(UINT128_ZERO.m_data[1] == 0);
        CHECK(UINT128_ZERO.m_data[2] == 0);
        CHECK(UINT128_ZERO.m_data[3] == 0);
        CHECK(UINT128_ONE.m_data[0] == 1);
        CHECK(UINT128_ONE.m_data[1] == 0);
        CHECK(UINT128_ONE.m_data[2] == 0);
        CHECK(UINT128_ONE.m_data[3] == 0);
    }

    SECTION("comparison") {
        CHECK      (make128u(1, 2, 3, 4) <  make128u(4, 3, 2, 1));
        CHECK      (make128u(1, 2, 3, 4) <= make128u(4, 3, 2, 1));
        CHECK_FALSE(make128u(1, 2, 3, 4) == make128u(4, 3, 2, 1));
        CHECK      (make128u(1, 2, 3, 4) != make128u(4, 3, 2, 1));
        CHECK_FALSE(make128u(1, 2, 3, 4) >= make128u(4, 3, 2, 1));
        CHECK_FALSE(make128u(1, 2, 3, 4) >  make128u(4, 3, 2, 1));
        CHECK_FALSE(make128u(4, 3, 2, 1) <  make128u(1, 2, 3, 4));
        CHECK_FALSE(make128u(4, 3, 2, 1) <= make128u(1, 2, 3, 4));
        CHECK_FALSE(make128u(4, 3, 2, 1) == make128u(1, 2, 3, 4));
        CHECK      (make128u(4, 3, 2, 1) != make128u(1, 2, 3, 4));
        CHECK      (make128u(4, 3, 2, 1) >= make128u(1, 2, 3, 4));
        CHECK      (make128u(4, 3, 2, 1) >  make128u(1, 2, 3, 4));
        CHECK_FALSE(make128u(5, 5, 5, 5) <  make128u(5, 5, 5, 5));
        CHECK      (make128u(5, 5, 5, 5) <= make128u(5, 5, 5, 5));
        CHECK      (make128u(5, 5, 5, 5) == make128u(5, 5, 5, 5));
        CHECK_FALSE(make128u(5, 5, 5, 5) != make128u(5, 5, 5, 5));
        CHECK      (make128u(5, 5, 5, 5) >= make128u(5, 5, 5, 5));
        CHECK_FALSE(make128u(5, 5, 5, 5) >  make128u(5, 5, 5, 5));
    }

    SECTION("conversion") {
        const uint256_t ref = make256u(1, 2, 3, 4, 5, 6, 7, 8);
        CHECK(bool(ref));           // Boolean (x != 0)
        CHECK(int32_t(ref) == 8);   // Convert to s32 / s64
        CHECK(int64_t(ref) == 0x700000008ll);
        CHECK(uint32_t(ref) == 8);  // Convert to u32 / u64
        CHECK(uint64_t(ref) == 0x700000008ull);
        const uint128_t uut1(ref);  // Truncate
        for (unsigned a = 0 ; a < 4 ; ++a) CHECK(uut1.m_data[a] == ref.m_data[a]);
        const uint512_t uut2(ref);  // Zero-pad
        for (unsigned a = 0 ; a < 8 ; ++a) CHECK(uut2.m_data[a] == ref.m_data[a]);
        for (unsigned a = 8 ; a < 16 ; ++a) CHECK(uut2.m_data[a] == 0);
    }

    SECTION("msb") {
        CHECK(make128u(0, 0, 0, 0).msb() == 0);
        CHECK(make128u(0, 0, 0, 15).msb() == 3);
        CHECK(make128u(0, 0, 0, 16).msb() == 4);
        CHECK(make128u(0, 0, 0, 17).msb() == 4);
        CHECK(make128u(0, 0, 0, UINT32_MAX).msb() == 31);
        CHECK(make128u(0, 0, 38, 5).msb() == 37);
        CHECK(make128u(0, 9, 99, 3).msb() == 67);
        CHECK(make128u(1, 7, 42, 8).msb() == 96);
        CHECK(make128u(UINT32_MAX, 0, 0, 0).msb() == 127);
    }

    SECTION("increment") {
        // Pre-increment/decrement
        CHECK(++make128u(0, 0, 0, 0) == make128u(0, 0, 0, 1));
        CHECK(++make128u(1, 2, 3, UINT32_MAX) == make128u(1, 2, 4, 0));
        CHECK(++make128u(UINT32_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX) == make128u(0, 0, 0, 0));
        CHECK(--make128u(0, 0, 0, 7) == make128u(0, 0, 0, 6));
        CHECK(--make128u(0, 0, 0, 0) == make128u(UINT32_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX));
        // Post-increment/decrement
        uint128_t uut1 = make128u(1, 2, 3, 4);
        CHECK(uut1++ == make128u(1, 2, 3, 4));
        CHECK(uut1++ == make128u(1, 2, 3, 5));
        CHECK(uut1-- == make128u(1, 2, 3, 6));
        CHECK(uut1-- == make128u(1, 2, 3, 5));
    }

    SECTION("addition") {
        uint128_t a = make128u(1, 2, 3, 4) + make128u(5, 6, 7, 8);
        CHECK(a == make128u(6, 8, 10, 12));
        uint128_t b = make128u(0, 0, 0, 1) + make128u(0, 0, 0, 0xFFFFFFFFu);
        CHECK(b == make128u(0, 0, 1, 0));
        uint128_t c = make128u(1, 2, 0xFFFFFFFFu, 3) + make128u(4, 5, 0xFFFFFFFFu, 6);
        CHECK(c == make128u(5, 8, 0xFFFFFFFEu, 9));
        uint128_t d = make128u(1, 2, 3, 4); d += make128u(5, 6, 7, 8);
        CHECK(d == make128u(6, 8, 10, 12));
        uint128_t e = make128u(0, 0, 0, 1); e += make128u(0, 0, 0, 0xFFFFFFFFu);
        CHECK(e == make128u(0, 0, 1, 0));
        uint128_t f = make128u(1, 2, 0xFFFFFFFFu, 3); f += make128u(4, 5, 0xFFFFFFFFu, 6);
        CHECK(f == make128u(5, 8, 0xFFFFFFFEu, 9));
        uint128_t g = make128u(1, 2, 0xFFFFFFFFu, 0xFFFFFFFFu) + make128u(3, 4, 0xFFFFFFFFu, 5);
        CHECK(g == make128u(4, 7, 0xFFFFFFFFu, 4));
        uint128_t h = make128u(1, 2, 0xFFFFFFFFu, 0xFFFFFFFFu); h += make128u(3, 4, 0xFFFFFFFFu, 5);
        CHECK(h == make128u(4, 7, 0xFFFFFFFFu, 4));
    }

    SECTION("addition3") {
        // Define three constants and their sum.
        const int128_t a((s64)-985604758632441288ll);
        const uint128_t b((u64)1007229118000000000ull);
        const uint128_t c((u64)104235472715776ull);
        const uint128_t isum((u64)21728594840274488ull);
        // Test all permutations of "+" operator.
        // (Addition is commutative, but is our implementation?)
        CHECK(a + b + c == isum);
        CHECK(a + c + b == isum);
        CHECK(b + a + c == isum);
        CHECK(b + c + a == isum);
        CHECK(c + a + b == isum);
        CHECK(c + b + a == isum);
        // Test all permutations of "+=" operator.
        {uint128_t x = a; x += b; x += c; CHECK(x == isum);}
        {uint128_t x = a; x += c; x += b; CHECK(x == isum);}
        {uint128_t x = b; x += a; x += c; CHECK(x == isum);}
        {uint128_t x = b; x += c; x += a; CHECK(x == isum);}
        {uint128_t x = c; x += a; x += b; CHECK(x == isum);}
        {uint128_t x = c; x += b; x += a; CHECK(x == isum);}
    }

    SECTION("subtraction") {
        CHECK(-make128u(0, 0, 0, 0) == make128u(0, 0, 0, 0));
        CHECK(-make128u(0, 0, 0, 1) == make128u(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        CHECK(make128u(5, 6, 7, 8)
            - make128u(1, 2, 3, 4)
           == make128u(4, 4, 4, 4));
        CHECK(make128u(0, 0, 0, 1)
            - make128u(0, 0, 0, 0xFFFFFFFFu)
           == make128u(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 2));
        CHECK(make128u(4, 5, 0xFFFFFFFFu, 6)
            - make128u(1, 2, 0xFFFFFFFFu, 3)
           == make128u(3, 3, 0, 3));
        CHECK(make128u(0, 1, 0x40D931FFu, 0x95EDDB30u)
            - make128u(0, 0, 0x5CB27800u, 0x25849BA1u)
           == make128u(0, 0, 0xE426B9FFu, 0x70693F8Fu));
        uint128_t a = make128u(5, 6, 7, 8); a -= make128u(5, 6, 7, 9);
        CHECK(a == make128u(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        uint128_t b = make128u(0, 0, 0, 1); b -= make128u(0, 0, 0, 0xFFFFFFFFu);
        CHECK(b == make128u(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 2));
        uint128_t c = make128u(4, 5, 0xFFFFFFFFu, 5); c -= make128u(4, 5, 0xFFFFFFFFu, 6);
        CHECK(c == make128u(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
    }

    SECTION("subtract3") {
        // Define three constants and their sum.
        const int128_t a((s64)-985604758632441288ll);
        const uint128_t b((u64)1007229118000000000ull);
        const uint128_t c((u64)104235472715776ull);
        const int128_t isum((s64)-21728594840274488ll);
        // Test all permutations of "-" operator.
        // (Addition is commutative, but is our implementation?)
        CHECK(-a - b - c == isum);
        CHECK(-a - c - b == isum);
        CHECK(-b - a - c == isum);
        CHECK(-b - c - a == isum);
        CHECK(-c - a - b == isum);
        CHECK(-c - b - a == isum);
        // Test all permutations of "-=" operator.
        {uint128_t x = -a; x -= b; x -= c; CHECK(x == isum);}
        {uint128_t x = -a; x -= c; x -= b; CHECK(x == isum);}
        {uint128_t x = -b; x -= a; x -= c; CHECK(x == isum);}
        {uint128_t x = -b; x -= c; x -= a; CHECK(x == isum);}
        {uint128_t x = -c; x -= a; x -= b; CHECK(x == isum);}
        {uint128_t x = -c; x -= b; x -= a; CHECK(x == isum);}
    }

    SECTION("multiplication") {
        // Note: Division tests also give the multiplier a thorough checkout.
        const uint128_t a = make128u(5, 6, 7, 8) * make128u(0, 0, 1, 2);
        CHECK(a == make128u(16, 19, 22, 16));
        uint128_t b = make128u(5, 6, 7, 8); b *= make128u(0, 0, 1, 2);
        CHECK(b == make128u(16, 19, 22, 16));
    }

    SECTION("mult_negative") {
        // Multiplication of negative numbers.
        const uint128_t a = make128u(5, 6, 7, 8);
        const uint128_t b = make128u(0, 0, 0, 3);
        const uint128_t c = make128u(0, 0, 4, 9);
        const uint128_t ab = a * b;
        const uint128_t ac = a * c;
        CHECK(-a *  b == -ab);
        CHECK( a * -b == -ab);
        CHECK(-a * -b ==  ab);
        CHECK(-a *  c == -ac);
        CHECK( a * -c == -ac);
        CHECK(-a * -c ==  ac);
    }

    SECTION("division") {
        // Random cross-checks of multiplication and division.
        for (unsigned a = 0 ; a < 1000 ; ++a) {
            uint128_t x, y, d, m;
            x = make128u(rng(), rng(), rng(), rng());
            y = make128u(rng(), rng(), rng(), rng());
            if (y == UINT128_ZERO) continue;
            x.divmod(y, d, m);
            if (x != y * d + m) {debug(x); debug(y); debug(d); debug(m);}
            CHECK(d <= x);
            CHECK(m <  y);
            CHECK(x == y * d + m);
        }
        // Additional checks for individual operators.
        CHECK(uint128_t(17u) / uint128_t(3u) == uint128_t(5u));
        CHECK(uint128_t(17u) % uint128_t(3u) == uint128_t(2u));
        {uint128_t a(17u); a /= uint128_t(3u); CHECK(a == uint128_t(5u));}
        {uint128_t a(17u); a %= uint128_t(3u); CHECK(a == uint128_t(2u));}
    }

    SECTION("fuzzer_add") {
        // Random cross-checks for self-consistency.
        for (unsigned a = 0 ; a < 1000 ; ++a) {
            // Randomize inputs.
            const uint128_t x = make128u(rng(), rng(), rng(), rng());
            const uint128_t y = make128u(rng(), rng(), rng(), rng());
            // Check that addition and subtraction are self-consistent.
            CHECK((x + y) == (y + x));
            CHECK((x - y) == -(y - x));
            CHECK((x - y) + y == x);
            CHECK((y - x) + x == y);
        }
    }

    SECTION("fuzzer_u64") {
        // Random cross-checks against built-in signed 64-bit arithmetic.
        for (unsigned a = 0 ; a < 1000 ; ++a) {
            // Randomize inputs.
            const u64 x1 = u64(rng()) << 32 | rng();
            const u64 y1 = u64(rng()) << 32 | rng();
            const uint128_t x2(x1);
            const uint128_t y2(y1);
            // Check the basic arithmetic operators.
            CHECK(u64(x1 + y1) == u64(x2 + y2));
            CHECK(u64(x1 - y1) == u64(x2 - y2));
            CHECK(u64(x1 * y1) == u64(x2 * y2));
            CHECK(u64(x1 | y1) == u64(x2 | y2));
            CHECK(u64(x1 & y1) == u64(x2 & y2));
            CHECK(u64(x1 ^ y1) == u64(x2 ^ y2));
            CHECK(u64(x1 >> 8u) == u64(x2 >> 8u));
        }
    }

    SECTION("bitshift") {
        const uint128_t MAX_POS = make128u(0x7FFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu);
        const uint128_t MAX_NEG = make128u(0x80000000u, 0, 0, 0);
        CHECK(make128u(1, 2, 3, 4) << 0u == make128u(1, 2, 3, 4));
        CHECK(make128u(1, 2, 3, 4) >> 0u == make128u(1, 2, 3, 4));
        CHECK(make128u(1, 2, 3, 4) << 32u == make128u(2, 3, 4, 0));
        CHECK(make128u(1, 2, 3, 4) >> 32u == make128u(0, 1, 2, 3));
        CHECK(make128u(0, 0, 0, 1) << 37u == make128u(0, 0, 32, 0));
        CHECK(make128u(0, 0, 32, 0) >> 37u == make128u(0, 0, 0, 1));
        CHECK(make128u(0, 0, 0, 1) << 127u == make128u(0x80000000u, 0, 0, 0));
        CHECK(MAX_POS >> 0u == MAX_POS);
        CHECK(MAX_POS >> 1u == make128u(0x3FFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        CHECK(MAX_POS >> 32u == make128u(0, 0x7FFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        CHECK(MAX_POS >> 37u == make128u(0, 0x03FFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        CHECK(MAX_POS >> 126u == UINT128_ONE);
        CHECK(MAX_NEG >> 0u == MAX_NEG);
        CHECK(MAX_NEG >> 1u == make128u(0x40000000u, 0, 0, 0));
        CHECK(MAX_NEG >> 32u == make128u(0, 0x80000000u, 0, 0));
        CHECK(MAX_NEG >> 37u == make128u(0, 0x04000000u, 0, 0));
        CHECK(MAX_NEG >> 127u == UINT128_ONE);
        uint128_t a = make128u(0, 0, 0xFFFFFFFFu, 0);
        a <<= 3u; CHECK(a == make128u(0, 0x07, 0xFFFFFFF8u, 0));
        a >>= 6u; CHECK(a == make128u(0, 0, 0x1FFFFFFFu, 0xE0000000u));
    }

    SECTION("bitwise") {
        uint128_t a = make128u(1, 2, 3, 4);
        CHECK((a | make128u(4, 3, 2, 1)) == make128u(5, 3, 3, 5));
        CHECK((a ^ make128u(4, 3, 2, 1)) == make128u(5, 1, 1, 5));
        CHECK((a & make128u(4, 3, 2, 1)) == make128u(0, 2, 2, 0));
        a |= make128u(0, 0, 0, 1); CHECK(a == make128u(1, 2, 3, 5));
        a ^= make128u(0, 0, 1, 0); CHECK(a == make128u(1, 2, 2, 5));
        a &= make128u(1, 1, 1, 1); CHECK(a == make128u(1, 0, 0, 1));
    }

    SECTION("logging") {
        satcat5::log::ToConsole logger;
        logger.disable();   // Don't echo to screen.
        const uint128_t a = make128u(1, 2, 3, 4);
        satcat5::log::Log(satcat5::log::INFO, "Test").write_obj(a);
        CHECK(logger.contains("0x00000001000000020000000300000004"));
    }

    SECTION("read-write") {
        u8 buff[64];
        satcat5::io::ArrayWrite uut(buff, sizeof(buff));
        const uint128_t a = make128u(1, 2, 3, 4);
        const uint256_t b = make256u(1, 2, 3, 4, 5, 6, 7, 8);

        uut.write_obj(a);
        uut.write_obj(b);
        uut.write_finalize();
        CHECK(uut.written_len() == 48);

        uint128_t c;
        uint256_t d, e;
        satcat5::io::ArrayRead rd(buff, uut.written_len());
        CHECK(rd.read_obj(c));          // Should succeed
        CHECK(rd.read_obj(d));          // Should succeed
        CHECK_FALSE(rd.read_obj(e));    // Intentional underflow
        CHECK(a == c);
        CHECK(b == d);
    }
}
