//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation
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
// Test cases for the wide-integer arithmetic class

#include <hal_test/catch.hpp>
#include <satcat5/uint_wide.h>

using namespace satcat5::util;

// Shortcut function for initializing longer constants.
uint128_t make128(u32 a, u32 b, u32 c, u32 d) {
    uint128_t tmp;
    tmp.m_data[3] = a; tmp.m_data[2] = b; tmp.m_data[1] = c; tmp.m_data[0] = d;
    return tmp;
}

uint256_t make256(u32 a, u32 b, u32 c, u32 d, u32 e, u32 f, u32 g, u32 h) {
    uint256_t tmp;
    tmp.m_data[7] = a; tmp.m_data[6] = b; tmp.m_data[5] = c; tmp.m_data[4] = d;
    tmp.m_data[3] = e; tmp.m_data[2] = f; tmp.m_data[1] = g; tmp.m_data[0] = h;
    return tmp;
}

void debug(const uint128_t& x) {
    printf("X = 0x%08X-%08X-%08X-%08X\n", x.m_data[3], x.m_data[2], x.m_data[1], x.m_data[0]);
}

TEST_CASE("uint_wide.h") {
    Catch::SimplePcg32 rng;

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
        CHECK      (make128(1, 2, 3, 4) <  make128(4, 3, 2, 1));
        CHECK      (make128(1, 2, 3, 4) <= make128(4, 3, 2, 1));
        CHECK_FALSE(make128(1, 2, 3, 4) == make128(4, 3, 2, 1));
        CHECK      (make128(1, 2, 3, 4) != make128(4, 3, 2, 1));
        CHECK_FALSE(make128(1, 2, 3, 4) >= make128(4, 3, 2, 1));
        CHECK_FALSE(make128(1, 2, 3, 4) >  make128(4, 3, 2, 1));
        CHECK_FALSE(make128(4, 3, 2, 1) <  make128(1, 2, 3, 4));
        CHECK_FALSE(make128(4, 3, 2, 1) <= make128(1, 2, 3, 4));
        CHECK_FALSE(make128(4, 3, 2, 1) == make128(1, 2, 3, 4));
        CHECK      (make128(4, 3, 2, 1) != make128(1, 2, 3, 4));
        CHECK      (make128(4, 3, 2, 1) >= make128(1, 2, 3, 4));
        CHECK      (make128(4, 3, 2, 1) >  make128(1, 2, 3, 4));
        CHECK_FALSE(make128(5, 5, 5, 5) <  make128(5, 5, 5, 5));
        CHECK      (make128(5, 5, 5, 5) <= make128(5, 5, 5, 5));
        CHECK      (make128(5, 5, 5, 5) == make128(5, 5, 5, 5));
        CHECK_FALSE(make128(5, 5, 5, 5) != make128(5, 5, 5, 5));
        CHECK      (make128(5, 5, 5, 5) >= make128(5, 5, 5, 5));
        CHECK_FALSE(make128(5, 5, 5, 5) >  make128(5, 5, 5, 5));
    }

    SECTION("conversion") {
        uint256_t ref = make256(1, 2, 3, 4, 5, 6, 7, 8);
        CHECK(bool(ref));           // Boolean (x != 0)
        CHECK(uint32_t(ref) == 8);  // Convert to u32 / u64
        CHECK(uint64_t(ref) == 0x700000008ull);
        uint128_t uut1(ref);        // Truncate
        for (unsigned a = 0 ; a < 4 ; ++a) CHECK(uut1.m_data[a] == ref.m_data[a]);
        uint512_t uut2(ref);        // Zero-pad
        for (unsigned a = 0 ; a < 8 ; ++a) CHECK(uut2.m_data[a] == ref.m_data[a]);
        for (unsigned a = 8 ; a < 16 ; ++a) CHECK(uut2.m_data[a] == 0);
    }

    SECTION("msb") {
        CHECK(make128(0, 0, 0, 0).msb() == 0);
        CHECK(make128(0, 0, 0, 15).msb() == 3);
        CHECK(make128(0, 0, 0, 16).msb() == 4);
        CHECK(make128(0, 0, 0, 17).msb() == 4);
        CHECK(make128(0, 0, 0, UINT32_MAX).msb() == 31);
        CHECK(make128(0, 0, 38, 5).msb() == 37);
        CHECK(make128(0, 9, 99, 3).msb() == 67);
        CHECK(make128(1, 7, 42, 8).msb() == 96);
        CHECK(make128(UINT32_MAX, 0, 0, 0).msb() == 127);
    }

    SECTION("increment") {
        // Pre-increment/decrement
        CHECK(++make128(0, 0, 0, 0) == make128(0, 0, 0, 1));
        CHECK(++make128(1, 2, 3, UINT32_MAX) == make128(1, 2, 4, 0));
        CHECK(++make128(UINT32_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX) == make128(0, 0, 0, 0));
        CHECK(--make128(0, 0, 0, 7) == make128(0, 0, 0, 6));
        CHECK(--make128(0, 0, 0, 0) == make128(UINT32_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX));
        // Post-increment/decrement
        uint128_t uut1 = make128(1, 2, 3, 4);
        CHECK(uut1++ == make128(1, 2, 3, 4));
        CHECK(uut1++ == make128(1, 2, 3, 5));
        CHECK(uut1-- == make128(1, 2, 3, 6));
        CHECK(uut1-- == make128(1, 2, 3, 5));
    }

    SECTION("addition") {
        uint128_t a = make128(1, 2, 3, 4) + make128(5, 6, 7, 8);
        CHECK(a == make128(6, 8, 10, 12));
        uint128_t b = make128(0, 0, 0, 1) + make128(0, 0, 0, 0xFFFFFFFFu);
        CHECK(b == make128(0, 0, 1, 0));
        uint128_t c = make128(1, 2, 0xFFFFFFFFu, 3) + make128(4, 5, 0xFFFFFFFFu, 6);
        CHECK(c == make128(5, 8, 0xFFFFFFFEu, 9));
        uint128_t d = make128(1, 2, 3, 4); d += make128(5, 6, 7, 8);
        CHECK(d == make128(6, 8, 10, 12));
        uint128_t e = make128(0, 0, 0, 1); e += make128(0, 0, 0, 0xFFFFFFFFu);
        CHECK(e == make128(0, 0, 1, 0));
        uint128_t f = make128(1, 2, 0xFFFFFFFFu, 3); f += make128(4, 5, 0xFFFFFFFFu, 6);
        CHECK(f == make128(5, 8, 0xFFFFFFFEu, 9));
        uint128_t g = make128(1, 2, 0xFFFFFFFFu, 0xFFFFFFFFu) + make128(3, 4, 0xFFFFFFFFu, 5);
        CHECK(g == make128(4, 7, 0xFFFFFFFFu, 4));
        uint128_t h = make128(1, 2, 0xFFFFFFFFu, 0xFFFFFFFFu); h += make128(3, 4, 0xFFFFFFFFu, 5);
        CHECK(h == make128(4, 7, 0xFFFFFFFFu, 4));
    }

    SECTION("subtraction") {
        CHECK(-make128(0, 0, 0, 0) == make128(0, 0, 0, 0));
        CHECK(-make128(0, 0, 0, 1) == make128(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        CHECK(make128(5, 6, 7, 8) - make128(1, 2, 3, 4) == make128(4, 4, 4, 4));
        CHECK(make128(0, 0, 0, 1) - make128(0, 0, 0, 0xFFFFFFFFu) == make128(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 2));
        CHECK(make128(4, 5, 0xFFFFFFFFu, 6) - make128(1, 2, 0xFFFFFFFFu, 3) == make128(3, 3, 0, 3));
        uint128_t a = make128(5, 6, 7, 8); a -= make128(5, 6, 7, 9);
        CHECK(a == make128(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
        uint128_t b = make128(0, 0, 0, 1); b -= make128(0, 0, 0, 0xFFFFFFFFu);
        CHECK(b == make128(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 2));
        uint128_t c = make128(4, 5, 0xFFFFFFFFu, 5); c -= make128(4, 5, 0xFFFFFFFFu, 6);
        CHECK(c == make128(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu));
    }

    SECTION("multiplication") {
        // Note: Division tests also give the multiplier a thorough checkout.
        uint128_t a = make128(5, 6, 7, 8) * make128(0, 0, 1, 2);
        CHECK(a == make128(16, 19, 22, 16));
        uint128_t b = make128(5, 6, 7, 8); b *= make128(0, 0, 1, 2);
        CHECK(b == make128(16, 19, 22, 16));
    }

    SECTION("division") {
        // Random cross-checks of multiplication and division.
        for (unsigned a = 0 ; a < 1000 ; ++a) {
            uint128_t x, y, d, m;
            x = make128(rng(), rng(), rng(), rng());
            y = make128(rng(), rng(), rng(), rng());
            if (y == UINT128_ZERO) continue;
            x.divmod(y, d, m);
            if (m >= y) {debug(x); debug(y); debug(d); debug(m);}
            CHECK(d <= x);
            CHECK(m <  y);
            CHECK(x == y * d + m);
        }
        // Additional checks for individual operators.
        CHECK(uint128_t(17u) / uint128_t(3u) == uint128_t(5u));
        CHECK(uint128_t(17u) % uint128_t(3u) == uint128_t(2u));
        uint128_t a(17u); a /= uint128_t(3u); CHECK(a == uint128_t(5u));
        uint128_t b(17u); b %= uint128_t(3u); CHECK(b == uint128_t(2u));
    }

    SECTION("bitshift") {
        CHECK(make128(0, 0, 0, 1) << 37u == make128(0, 0, 32, 0));
        CHECK(make128(0, 0, 32, 0) >> 37u == make128(0, 0, 0, 1));
        CHECK(make128(0, 0, 0, 1) << 127u == make128(0x80000000u, 0, 0, 0));
        CHECK(make128(0x80000000u, 0, 0, 0) >> 127u == make128(0, 0, 0, 1));
        uint128_t a = make128(0, 0, 0xFFFFFFFFu, 0);
        a <<= 3u; CHECK(a == make128(0, 0x07, 0xFFFFFFF8u, 0));
        a >>= 6u; CHECK(a == make128(0, 0, 0x1FFFFFFFu, 0xE0000000u));
    }

    SECTION("bitwise") {
        uint128_t a = make128(1, 2, 3, 4);
        CHECK((a | make128(4, 3, 2, 1)) == make128(5, 3, 3, 5));
        CHECK((a ^ make128(4, 3, 2, 1)) == make128(5, 1, 1, 5));
        CHECK((a & make128(4, 3, 2, 1)) == make128(0, 2, 2, 0));
        a |= make128(0, 0, 0, 1); CHECK(a == make128(1, 2, 3, 5));
        a ^= make128(0, 0, 1, 0); CHECK(a == make128(1, 2, 2, 5));
        a &= make128(1, 1, 1, 1); CHECK(a == make128(1, 0, 0, 1));
    }
}
