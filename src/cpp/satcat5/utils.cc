//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/utils.h>

namespace util = satcat5::util;

u32 util::max_u32(u32 a, u32 b, u32 c) {
    if ((a > b) && (a > c)) return a;
    if (b > c) return b;
    return c;
}

// Check if A is a multiple of B:
bool util::is_multiple_u32(u32 a, u32 b)
{
    u32 c = (a / b) * b;
    return (a == c) ? 1 : 0;
}

// XOR-reduction of all bits in a word (returns 1/0).
bool util::xor_reduce_u8(u8 x)
{
    u8 result = 0;
    for (unsigned b = 0 ; b < 8 ; ++b)
        result ^= ((x >> b) & 1);
    return result ? 1 : 0;
}
bool util::xor_reduce_u16(u16 x)
{
    u16 result = 0;
    for (unsigned b = 0 ; b < 16 ; ++b)
        result ^= ((x >> b) & 1);
    return result ? 1 : 0;
}
bool util::xor_reduce_u32(u32 x)
{
    u32 result = 0;
    for (unsigned b = 0 ; b < 32 ; ++b)
        result ^= ((x >> b) & 1);
    return result ? 1 : 0;
}
bool util::xor_reduce_u64(u64 x)
{
    u64 result = 0;
    for (unsigned b = 0 ; b < 64 ; ++b)
        result ^= ((x >> b) & 1);
    return result ? 1 : 0;
}

// Given X and Y, find the minimum N such that X * 2^N >= Y.
unsigned util::min_2n(u32 x, u32 y)
{
    static const u32 HALF_MAX = (1u << 31);

    // Detect invalid input (i.e., divide by zero).
    // Undefined, just do anything that avoids an infinite loop.
    if (x == 0) ++x;

    // Increment N until constraint is *almost* met.
    // (Stop just short to avoid overflow when Y is very large.)
    unsigned n = 0;
    while ((x < HALF_MAX) && (2*x < y)) {
        x *= 2;
        ++n;
    }

    // One last increment if needed.
    if (x < y) ++n;
    return n;
}

// Find integer square root y = floor(sqrt(x))
// https://stackoverflow.com/questions/4930307/fastest-way-to-get-the-integer-part-of-sqrtn
u32 util::sqrt_u64(u64 x)
{
    u64 rem = 0, root = 0;
    for (unsigned i = 0 ; i < 32 ; ++i) {
        root <<= 1;
        rem <<= 2;
        rem += (x >> 62);
        x <<= 2;

        if (root < rem) {
            root++;
            rem -= root;
            root++;
        }
    }
    return (u32) (root >> 1);
}
u16 util::sqrt_u32(u32 x)
{
    u32 rem = 0, root = 0;
    for (unsigned i = 0 ; i < 16 ; ++i) {
        root <<= 1;
        rem <<= 2;
        rem += (x >> 30);
        x <<= 2;

        if (root < rem) {
            root++;
            rem -= root;
            root++;
        }
    }
    return (u16) (root >> 1);
}
u8 util::sqrt_u16(u16 x)
{
    u16 rem = 0, root = 0;
    int i;
    for (i = 0 ; i < 8 ; ++i) {
        root <<= 1;
        rem <<= 2;
        rem += (x >> 14);
        x <<= 2;

        if (root < rem) {
            root++;
            rem -= root;
            root++;
        }
    }
    return (u8) (root >> 1);
}


// Extract fields from a big-endian byte array.
u16 util::extract_be_u16(const u8* src)
{
    return 256 * (u16)src[0]
         +   1 * (u16)src[1];
}
u32 util::extract_be_u32(const u8* src)
{
    return 16777216 * (u32)src[0]
         +    65536 * (u32)src[1]
         +      256 * (u32)src[2]
         +        1 * (u32)src[3];
}
u64 util::extract_be_u64(const u8* src)
{
    return 72057594037927936ull * (u64)src[0]
         +   281474976710656ull * (u64)src[1]
         +     1099511627776ull * (u64)src[2]
         +        4294967296ull * (u64)src[3]
         +          16777216ull * (u64)src[4]
         +             65536ull * (u64)src[5]
         +               256ull * (u64)src[6]
         +                 1ull * (u64)src[7];
}

// Store fields into a big-endian byte array.
void util::write_be_u16(u8* dst, u16 val)
{
    dst[0] = (u8)(val >> 8);
    dst[1] = (u8)(val >> 0);
}
void util::write_be_u32(u8* dst, u32 val)
{
    dst[0] = (u8)(val >> 24);
    dst[1] = (u8)(val >> 16);
    dst[2] = (u8)(val >> 8);
    dst[3] = (u8)(val >> 0);
}
void util::write_be_u64(u8* dst, u64 val)
{
    dst[0] = (u8)(val >> 56);
    dst[1] = (u8)(val >> 48);
    dst[2] = (u8)(val >> 40);
    dst[3] = (u8)(val >> 32);
    dst[4] = (u8)(val >> 24);
    dst[5] = (u8)(val >> 16);
    dst[6] = (u8)(val >> 8);
    dst[7] = (u8)(val >> 0);
}

u32 util::Prng::next()
{
    // Marsaglia's XORSHIFT algorithm:
    m_state ^= (m_state >> 12);
    m_state ^= (m_state << 25);
    m_state ^= (m_state >> 27);
    u64 next = m_state * 0x2545F4914F6CDD1Dull;
    return (u32)(next >> 32);
}

static const char* LABEL_NONE = "None";

util::RunningMax::RunningMax()
    : m_label(LABEL_NONE)
    , m_maximum(0)
{
    // Nothing else to initialize
}

void util::RunningMax::clear()
{
    m_label = LABEL_NONE;
    m_maximum = 0;
}

void util::RunningMax::update(const char* lbl, u32 value)
{
    if (value > m_maximum) {
        m_label = lbl;
        m_maximum = value;
    }
}
