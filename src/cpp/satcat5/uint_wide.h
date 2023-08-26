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
// Wide-integer arithmetic
//
// Since the C++0x11 standard does not define integer types wider than
// 64 bits (i.e., uint64_t), we need to get creative.  This file defines
// a templated struct that behaves like a very wide unsigned integer,
// including the same modulo-arithmetic guarantees.  Type and constant
// shorthand are provided for commonly-used sizes (uint128_t, uint256_t).

#pragma once

#include <climits>
#include <satcat5/io_core.h>
#include <satcat5/log.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace util {
        // Define the template struct.  "W" the is number of 32-bit subunits.
        template <unsigned W> struct UintWide {
            // Underlying data vector, LSW-first.
            u32 m_data[W];

            // Constructors and assignment.
            // Note: Nested templates are used to allow size conversion.
            UintWide() = default;
            constexpr explicit UintWide(u32 rhs)
                : m_data{u32(rhs)} {}
            constexpr explicit UintWide(u64 rhs)
                : m_data{u32(rhs >> 0), u32(rhs >> 32)} {}
            explicit UintWide(s32 rhs)
                : m_data{u32(rhs)} {
                for (unsigned a = 1 ; a < W ; ++a)
                    m_data[a] = sign_extend(rhs);
            }
            explicit UintWide(s64 rhs)
                : m_data{u32(rhs >> 0), u32(rhs >> 32)} {
                for (unsigned a = 2 ; a < W ; ++a)
                    m_data[a] = sign_extend(rhs);
            }
            constexpr UintWide(u32 hi, u32 lo)
                : m_data{lo, hi} {}
            template <unsigned W2> explicit UintWide(const UintWide<W2>& rhs) {
                for (unsigned a = 0 ; a < W ; ++a) {
                    m_data[a] = (a < W2) ? rhs.m_data[a] : 0;
                }
            }
            UintWide<W>& operator=(u32 rhs) {
                if (W > 0) m_data[0] = rhs;
                for (unsigned a = 1 ; a < W ; ++a) {
                    m_data[a] = 0;
                }
                return *this;
            }
            template <unsigned W2> UintWide<W>& operator=(const UintWide<W2>& rhs) {
                for (unsigned a = 0 ; a < W ; ++a) {
                    m_data[a] = (a < W2) ? rhs.m_data[a] : 0;
                }
                return *this;
            }

            // Total width in bits or in words.
            inline unsigned width_bits() const { return 32 * W; }
            inline unsigned width_words() const { return W; }

            // Index of most significant '1' bit.
            unsigned msb() const {
                for (unsigned w = W-1 ; w < UINT_MAX ; --w) {
                    if (m_data[w] == 0) continue;
                    for (unsigned b = 31 ; b < 32 ; --b) {
                        if (m_data[w] & (1u << b)) return 32*w+b;
                    }
                }
                return 0;
            }

            // Combined divide + modulo function.
            void divmod(const UintWide<W>& rhs, UintWide<W>& div, UintWide<W>& mod) const {
                // Shortcuts for unusual edge-cases.
                static constexpr UintWide<W> ZERO(0u);
                static constexpr UintWide<W> ONE(1u);
                if (rhs <= ONE)     {div = *this; mod = ZERO;  return;}
                if (*this == rhs)   {div = ONE;   mod = ZERO;  return;}
                if (*this < rhs)    {div = ZERO;  mod = *this; return;}
                // Order-of-magnitude estimate of the result.
                unsigned msb = 1 + this->msb() - rhs.msb();
                // Use the serial bit-at-a-time method.
                mod = *this; div = ZERO;
                for (unsigned b = msb ; b < UINT_MAX ; --b) {
                    UintWide<W> tmp(rhs << b);
                    if (mod >= tmp) {
                        div.m_data[b/32] |= (1u << (b%32));
                        mod -= tmp;
                    }
                }
            }

            // Increment/decrement.
            UintWide<W>& operator++() {     // ++myint
                if (W > 0) ++m_data[0];
                for (unsigned a = 0 ; a+1 < W ; ++a) {
                    if (m_data[a] != 0) break;
                    else ++m_data[a+1];
                }
                return *this;
            }
            UintWide<W>& operator--() {     // --myint
                if (W > 0) --m_data[0];
                for (unsigned a = 0 ; a+1 < W ; ++a) {
                    if (m_data[a] != UINT32_MAX) break;
                    else --m_data[a+1];
                }
                return *this;
            }
            UintWide<W> operator++(int) {  // myint++
                UintWide<W> tmp(*this); operator++(); return tmp;
            }
            UintWide<W> operator--(int) {  // myint--
                UintWide<W> tmp(*this); operator--(); return tmp;
            }

            // Arithmetic operators.
            UintWide<W> operator+(const UintWide<W>& rhs) const {
                // Modulo-add all the individual terms.
                UintWide<W> tmp;
                for (unsigned a = 0 ; a < W ; ++a) {
                    tmp.m_data[a] = m_data[a] + rhs.m_data[a];
                }
                // Wraparound on any term gives +1 carry to the next term.
                // Special case if that's just enough to double-rollover.
                bool carry = false;
                for (unsigned a = 0 ; a+1 < W ; ++a) {
                    if (tmp.m_data[a] < rhs.m_data[a]) {
                        ++tmp.m_data[a+1]; carry = true;
                    } else if (carry && tmp.m_data[a] == rhs.m_data[a]) {
                        ++tmp.m_data[a+1]; carry = true;
                    } else {
                        carry = false;
                    }
                }
                return tmp;
            }
            UintWide<W>& operator+=(const UintWide<W>& rhs) {
                // Modulo-add all the individual terms.
                for (unsigned a = 0 ; a < W ; ++a) {
                    m_data[a] += rhs.m_data[a];
                }
                // Wraparound on any term gives +1 carry to the next term.
                // Special case if that's just enough to double-rollover.
                bool carry = false;
                for (unsigned a = 0 ; a+1 < W ; ++a) {
                    if (m_data[a] < rhs.m_data[a]) {
                        ++m_data[a+1]; carry = true;
                    } else if (carry && m_data[a] == rhs.m_data[a]) {
                        ++m_data[a+1]; carry = true;
                    } else {
                        carry = false;
                    }
                }
                return *this;
            }

            inline UintWide<W> operator-() const {
                UintWide<W> tmp(~(*this)); ++tmp; return tmp;
            }
            UintWide<W> operator-(const UintWide<W>& rhs) const {
                // Modulo-subtract all the individual terms.
                UintWide<W> tmp;
                for (unsigned a = 0 ; a < W ; ++a) {
                    tmp.m_data[a] = m_data[a] - rhs.m_data[a];
                }
                // Wraparound on any term gives -1 carry from the next term.
                // Special case if that's just enough to double-rollover.
                bool carry = false;
                for (unsigned a = 0 ; a+1 < W ; ++a) {
                    if (tmp.m_data[a] > m_data[a]) {
                        --tmp.m_data[a+1]; carry = true;
                    } else if (carry && tmp.m_data[a] == rhs.m_data[a]) {
                        --tmp.m_data[a+1]; carry = true;
                    } else {
                        carry = false;
                    }
                }
                return tmp;
            }
            inline UintWide<W>& operator-=(const UintWide<W>& rhs) {
                *this = *this - rhs; return *this;
            }

            UintWide<W> operator*(const UintWide<W>& rhs) const {
                // Calculate, scale, and sum each of the inner-product terms.
                // (Skip any that fall outside the useful dynamic range.)
                UintWide<W> sum(u32(0));
                for (unsigned a = 0 ; a < W ; ++a) {
                    for (unsigned b = 0 ; a + b < W ; ++b) {
                        u64 aa = (u64)m_data[a];
                        u64 bb = (u64)rhs.m_data[b];
                        UintWide<W> p(aa * bb);
                        unsigned scale = 32 * (a + b);
                        sum += (p << scale);
                    }
                }
                return sum;
            }
            UintWide<W>& operator*=(const UintWide<W>& rhs) {
                *this = *this * rhs; return *this;
            }

            inline UintWide<W> operator/(const UintWide<W>& rhs) const {
                UintWide<W> d, m; this->divmod(rhs, d, m); return d;
            }
            inline UintWide<W> operator%(const UintWide<W>& rhs) const {
                UintWide<W> d, m; this->divmod(rhs, d, m); return m;
            }
            inline UintWide<W>& operator/=(const UintWide<W>& rhs) {
                *this = *this / rhs; return *this;
            }
            inline UintWide<W>& operator%=(const UintWide<W>& rhs) {
                *this = *this % rhs; return *this;
            }

            // Bit-shift operators.
            UintWide<W> operator<<(unsigned rhs) const {
                unsigned rw = rhs / 32;     // Words to shift
                unsigned rb = rhs % 32;     // Bits to shift
                unsigned rc = 32 - rb;      // Complement of rb
                UintWide<W> tmp;
                for (unsigned a = 0 ; a < W ; ++a) {
                    u32 hi = (a >= rw) ? (m_data[a-rw] << rb) : 0;
                    u32 lo = (rb && a > rw) ? (m_data[a-rw-1] >> rc) : 0;
                    tmp.m_data[a] = hi | lo;
                }
                return tmp;
            }
            UintWide<W> operator>>(unsigned rhs) const {
                unsigned rw = rhs / 32;     // Words to shift
                unsigned rb = rhs % 32;     // Bits to shift
                unsigned rc = 32 - rb;      // Complement of rb
                UintWide<W> tmp;
                for (unsigned a = 0 ; a < W ; ++a) {
                    u32 hi = (a+rw+1 < W) ? (m_data[a+rw+1] << rc) : 0;
                    u32 lo = (rb && a+rw < W) ? (m_data[a+rw] >> rb) : 0;
                    tmp.m_data[a] = hi | lo;
                }
                return tmp;
            }

            inline UintWide operator<<=(unsigned rhs) {
                *this = *this << rhs; return *this;
            }
            inline UintWide operator>>=(unsigned rhs) {
                *this = *this >> rhs; return *this;
            }

            // Bitwise logical operators.
            UintWide<W> operator~() const {
                UintWide<W> tmp;
                for (unsigned a = 0 ; a < W ; ++a) {
                    tmp.m_data[a] = ~m_data[a];
                }
                return tmp;
            }

            UintWide<W>& operator|=(const UintWide<W>& rhs) {
                for (unsigned a = 0 ; a < W ; ++a) {
                    m_data[a] |= rhs.m_data[a];
                }
                return *this;
            }
            UintWide<W>& operator&=(const UintWide<W>& rhs) {
                for (unsigned a = 0 ; a < W ; ++a) {
                    m_data[a] &= rhs.m_data[a];
                }
                return *this;
            }
            UintWide<W>& operator^=(const UintWide<W>& rhs) {
                for (unsigned a = 0 ; a < W ; ++a) {
                    m_data[a] ^= rhs.m_data[a];
                }
                return *this;
            }

            inline UintWide<W> operator|(const UintWide<W>& rhs) const {
                UintWide<W> tmp(*this); tmp |= rhs; return tmp;
            }
            inline UintWide<W> operator&(const UintWide<W>& rhs) const {
                UintWide<W> tmp(*this); tmp &= rhs; return tmp;
            }
            inline UintWide<W> operator^(const UintWide<W>& rhs) const {
                UintWide<W> tmp(*this); tmp ^= rhs; return tmp;
            }

            // Comparison operators.
            bool operator==(const UintWide<W>& rhs) const {
                unsigned match = 0;
                for (unsigned a = 0 ; a < W ; ++a) {
                    if (m_data[a] == rhs.m_data[a]) ++match;
                }
                return (match == W);
            }
            bool operator<(const UintWide<W>& rhs) const {
                for (unsigned a = W-1 ; a < UINT_MAX ; --a) {
                    if (m_data[a] < rhs.m_data[a]) return true;
                    if (m_data[a] > rhs.m_data[a]) return false;
                }
                return false;   // All fields equal.
            }
            bool operator>(const UintWide<W>& rhs) const {
                for (unsigned a = W-1 ; a < UINT_MAX ; --a) {
                    if (m_data[a] > rhs.m_data[a]) return true;
                    if (m_data[a] < rhs.m_data[a]) return false;
                }
                return false;   // All fields equal.
            }
            inline bool operator!=(const UintWide<W>& rhs) const {
                return !operator==(rhs);
            }
            inline bool operator<=(const UintWide<W>& rhs) const {
                return !operator>(rhs);
            }
            inline bool operator>=(const UintWide<W>& rhs) const {
                return !operator<(rhs);
            }

            // Conversion operators.
            operator bool() const {
                u32 any = 0;
                for (unsigned a = 0 ; a < W ; ++a) {
                    any |= m_data[a];
                }
                return (any > 0);
            }
            constexpr operator int32_t() const {
                return (int32_t)uint32_t(*this);
            }
            constexpr operator int64_t() const {
                return (int64_t)uint64_t(*this);
            }
            constexpr operator uint32_t() const {
                return (W > 0) ? m_data[0] : 0;
            }
            constexpr operator uint64_t() const {
                return u64((W > 1) ? m_data[1] : 0) << 32
                     | u64((W > 0) ? m_data[0] : 0);
            }

            // Binary and human-readable I/O methods.
            void log_to(satcat5::log::LogBuffer& obj) const {
                obj.wr_str(" = 0x");
                for (unsigned a = W-1 ; a < UINT_MAX ; --a) {
                    obj.wr_hex(m_data[a], 8);
                }
            }

            bool read_from(satcat5::io::Readable* rd) {
                if (rd->get_read_ready() >= 4*W) {
                    for (unsigned a = W-1 ; a < UINT_MAX ; --a) {
                        m_data[a] = rd->read_u32();
                    }
                    return true;
                } else {
                    return false;
                }
            }

            void write_to(satcat5::io::Writeable* wr) const {
                for (unsigned a = W-1 ; a < UINT_MAX ; --a) {
                    wr->write_u32(m_data[a]);
                }
            }

        private:
            // Helper function for sign-extension.
            template <typename T> inline constexpr u32 sign_extend(T x)
                { return u32((x < 0) ? -1 : 0); }
        };

        // Shorthand for commonly used sizes.
        typedef satcat5::util::UintWide<4> uint128_t;
        typedef satcat5::util::UintWide<8> uint256_t;
        typedef satcat5::util::UintWide<16> uint512_t;

        // Shorthand for commonly used constants.
        constexpr satcat5::util::uint128_t UINT128_ZERO(u32(0));
        constexpr satcat5::util::uint256_t UINT256_ZERO(u32(0));
        constexpr satcat5::util::uint512_t UINT512_ZERO(u32(0));
        constexpr satcat5::util::uint128_t UINT128_ONE(u32(1));
        constexpr satcat5::util::uint256_t UINT256_ONE(u32(1));
        constexpr satcat5::util::uint512_t UINT512_ONE(u32(1));
    }
}
