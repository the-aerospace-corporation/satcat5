//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Wide-integer arithmetic
//
// Since the C++0x11 standard does not define integer types wider than
// 64 bits (i.e., uint64_t), we need to get creative.  This file defines
// a templated struct that behaves like a very wide integer, signed or
// unsigned, including the same modulo-arithmetic guarantees.  These are
// effectively fixed-width BigInteger analogues.  Shorthand is provided
// for commonly-used sizes (e.g., int128_t, uint128_t, uint256_t).

#pragma once

#include <climits>
#include <satcat5/io_core.h>
#include <satcat5/log.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace util {
        // Define the parent template for shared signed and unsigned functions.
        // This is not used directly; instead use WideSigned or WideUnsigned.
        // The "W" parameter the is number of 32-bit subunits.
        template <unsigned W> struct WideInteger {
        public:
            // Underlying data vector, LSW-first.
            u32 m_data[W];

            // Implicit size-converting copy constructors must know
            // if the input is signed or unsigned to proceed.
            template <unsigned W2>
            WideInteger(const satcat5::util::WideSigned<W2>& rhs) // NOLINT
                { copy_from<W2>(rhs, rhs.sign_extend()); }

            template <unsigned W2>
            WideInteger(const satcat5::util::WideUnsigned<W2>& rhs) // NOLINT
                { copy_from<W2>(rhs, 0); }

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

            // Extend most significant word with either "0" or "FFFF...".
            inline constexpr u32 sign_extend() const
                { return sign_extend(s32(m_data[W-1])); }

            // Increment/decrement.
            WideInteger<W>& operator++() {     // ++myint
                if (W > 0) ++m_data[0];
                for (unsigned a = 0 ; a+1 < W ; ++a) {
                    if (m_data[a] != 0) break;
                    else ++m_data[a+1];
                }
                return *this;
            }
            WideInteger<W>& operator--() {     // --myint
                if (W > 0) --m_data[0];
                for (unsigned a = 0 ; a+1 < W ; ++a) {
                    if (m_data[a] != UINT32_MAX) break;
                    else --m_data[a+1];
                }
                return *this;
            }
            WideInteger<W> operator++(int) {  // myint++
                WideInteger<W> tmp(*this); operator++(); return tmp;
            }
            WideInteger<W> operator--(int) {  // myint--
                WideInteger<W> tmp(*this); operator--(); return tmp;
            }

            // Equality comparison only; others require signed/unsigned specialization.
            bool operator==(const WideInteger<W>& rhs) const {
                unsigned match = 0;
                for (unsigned a = 0 ; a < W ; ++a) {
                    if (m_data[a] == rhs.m_data[a]) ++match;
                }
                return (match == W);
            }

            inline bool operator!=(const WideInteger<W>& rhs) const {
                return !operator==(rhs);
            }

            // Conversion to other basic types.
            explicit operator bool() const {
                u32 any = 0;
                for (unsigned a = 0 ; a < W ; ++a) {
                    any |= m_data[a];
                }
                return (any > 0);
            }
            explicit constexpr operator int32_t() const {
                return (int32_t)uint32_t(*this);
            }
            explicit constexpr operator int64_t() const {
                return (int64_t)uint64_t(*this);
            }
            explicit constexpr operator uint32_t() const {
                return (W > 0) ? m_data[0] : 0;
            }
            explicit constexpr operator uint64_t() const {
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

        protected:
            friend satcat5::util::WideSigned<W>;
            friend satcat5::util::WideUnsigned<W>;

            // Constructors are private to force use of child classes.
            // Note: Nested templates are used to allow size conversion.
            WideInteger() = default;
            constexpr explicit WideInteger(u32 rhs)
                : m_data{u32(rhs)} {}
            constexpr explicit WideInteger(u64 rhs)
                : m_data{u32(rhs >> 0), u32(rhs >> 32)} {}
            constexpr WideInteger(u32 hi, u32 lo)
                : m_data{lo, hi} {}

            explicit WideInteger(s32 rhs)
                : m_data{u32(rhs)}
            {
                for (unsigned a = 1 ; a < W ; ++a)
                    m_data[a] = sign_extend(rhs);
            }

            explicit WideInteger(s64 rhs)
                : m_data{u32(rhs >> 0), u32(rhs >> 32)}
            {
                for (unsigned a = 2 ; a < W ; ++a)
                    m_data[a] = sign_extend(rhs);
            }

            // Internal helper functions.
            template <typename T> inline constexpr u32 sign_extend(T x)
                { return u32((x < 0) ? -1 : 0); }

            template <unsigned W2>
            void copy_from(const satcat5::util::WideInteger<W2>& rhs, u32 ext) {
                for (unsigned a = 0 ; a < W ; ++a) {
                    m_data[a] = (a < W2) ? rhs.m_data[a] : ext;
                }
            }

            // Internal arithmetic functions.
            // Note: These cannot be inherited directly because we need the
            //   signed/unsigned type to be retained, so we use indirection.
            WideInteger<W> add(const WideInteger<W>& rhs) const {
                // Modulo-add all the individual terms.
                WideInteger<W> tmp;
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

            void add_in_place(const WideInteger<W>& rhs) {
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
            }

            WideInteger<W> subtract(const WideInteger<W>& rhs) const {
                // Modulo-subtract all the individual terms.
                WideInteger<W> tmp;
                for (unsigned a = 0 ; a < W ; ++a) {
                    tmp.m_data[a] = m_data[a] - rhs.m_data[a];
                }
                // Wraparound on any term gives -1 carry from the next term.
                // Special case if that's just enough to double-rollover.
                bool carry = false;
                for (unsigned a = 0 ; a+1 < W ; ++a) {
                    if (rhs.m_data[a] > m_data[a]) {
                        --tmp.m_data[a+1]; carry = true;
                    } else if (carry && rhs.m_data[a] == m_data[a]) {
                        --tmp.m_data[a+1]; carry = true;
                    } else {
                        carry = false;
                    }
                }
                return tmp;
            }

            WideInteger<W> multiply(const WideInteger<W>& rhs) const {
                // Calculate, scale, and sum each of the inner-product terms.
                // (Skip any that fall outside the useful dynamic range.)
                WideInteger<W> sum(u32(0));
                for (unsigned a = 0 ; a < W ; ++a) {
                    for (unsigned b = 0 ; a + b < W ; ++b) {
                        u64 aa = (u64)m_data[a];
                        u64 bb = (u64)rhs.m_data[b];
                        WideInteger<W> p(aa * bb);
                        unsigned scale = 32 * (a + b);
                        sum.add_in_place(p.shift_left(scale));
                    }
                }
                return sum;
            }

            WideInteger<W> shift_left(unsigned rhs) const {
                unsigned rw = rhs / 32;     // Words to shift
                unsigned rb = rhs % 32;     // Bits to shift
                unsigned rc = 32 - rb;      // Complement of rb
                WideInteger<W> tmp;
                for (unsigned a = 0 ; a < W ; ++a) {
                    u32 hi = (a >= rw) ? (m_data[a-rw] << rb) : 0;
                    u32 lo = (rb && a > rw) ? (m_data[a-rw-1] >> rc) : 0;
                    tmp.m_data[a] = hi | lo;
                }
                return tmp;
            }

            WideInteger<W> shift_right(unsigned rhs, u32 ext) const {
                unsigned rw = rhs / 32;     // Words to shift
                unsigned rb = rhs % 32;     // Bits to shift
                unsigned rc = 32 - rb;      // Complement of rb
                WideInteger<W> tmp;
                for (unsigned a = 0 ; a < W ; ++a) {
                    u32 hi = (a+rw+1 < W) ? m_data[a+rw+1] : ext;
                    u32 lo = (a+rw < W) ? m_data[a+rw] : ext;
                    tmp.m_data[a] = rb ? ((hi << rc) | (lo >> rb)) : lo;
                }
                return tmp;
            }

            WideInteger<W> bitwise_invert() const {
                WideInteger<W> tmp;
                for (unsigned a = 0 ; a < W ; ++a) {
                    tmp.m_data[a] = ~m_data[a];
                }
                return tmp;
            }

            void bitwise_or(const WideInteger<W>& rhs) {
                for (unsigned a = 0 ; a < W ; ++a) {
                    m_data[a] |= rhs.m_data[a];
                }
            }

            void bitwise_and(const WideInteger<W>& rhs) {
                for (unsigned a = 0 ; a < W ; ++a) {
                    m_data[a] &= rhs.m_data[a];
                }
            }

            void bitwise_xor(const WideInteger<W>& rhs) {
                for (unsigned a = 0 ; a < W ; ++a) {
                    m_data[a] ^= rhs.m_data[a];
                }
            }
        };

        // Template for signed integers.
        template <unsigned W> struct WideSigned final
            : public satcat5::util::WideInteger<W>
        {
        public:
            // Forward selected constructors.
            constexpr WideSigned()
                : satcat5::util::WideInteger<W>() {}
            constexpr explicit WideSigned(u32 rhs)
                : satcat5::util::WideInteger<W>(rhs) {}
            constexpr explicit WideSigned(u64 rhs)
                : satcat5::util::WideInteger<W>(rhs) {}
            constexpr WideSigned(u32 hi, u32 lo)
                : satcat5::util::WideInteger<W>(hi, lo) {}
            explicit WideSigned(s32 rhs)
                : satcat5::util::WideInteger<W>(rhs) {}
            explicit WideSigned(s64 rhs)
                : satcat5::util::WideInteger<W>(rhs) {}
            WideSigned(const satcat5::util::WideInteger<W>& rhs)
                { this->copy_from(rhs, 0); }
            WideSigned<W>& operator=(const WideInteger<W>& rhs)
                { this->copy_from(rhs, 0); return *this; }

            // Signed operations.
            bool is_negative() const {
                return this->m_data[W-1] >= 0x80000000u;
            }

            satcat5::util::WideSigned<W> abs() const {
                return is_negative() ? -(*this) : (*this);
            }

            void clamp(const WideSigned<W>& limit_pos) {
                const WideSigned<W> limit_neg(-limit_pos);
                if (*this > limit_pos) *this = limit_pos;
                if (*this < limit_neg) *this = limit_neg;
            }

            // Most arithmetic operations are thin wrappers.
            // Returned type always matches the first argument.
            WideSigned<W> operator-() const
                { WideSigned<W> tmp(~(*this)); ++tmp; return tmp; }
            inline WideSigned<W> operator+(const WideInteger<W>& rhs) const
                { return this->add(rhs); }
            inline WideSigned<W>& operator+=(const WideInteger<W>& rhs)
                { this->add_in_place(rhs); return *this; }
            inline WideSigned<W> operator-(const WideInteger<W>& rhs) const
                { return this->subtract(rhs); }
            inline WideSigned<W>& operator-=(const WideInteger<W>& rhs)
                { *this = this->subtract(rhs); return *this; }
            inline WideSigned<W> operator*(const WideInteger<W>& rhs) const
                { return this->multiply(rhs); }
            inline WideSigned<W>& operator*=(const WideInteger<W>& rhs)
                { *this = this->multiply(rhs); return *this; }
            inline WideSigned<W> operator/(const WideSigned<W>& rhs) const
                { WideSigned<W> d, m; this->divmod(rhs, d, m); return d; }
            inline WideSigned<W> operator%(const WideSigned<W>& rhs) const
                { WideSigned<W> d, m; this->divmod(rhs, d, m); return m; }
            inline WideSigned<W>& operator/=(const WideInteger<W>& rhs)
                { *this = *this / rhs; return *this; }
            inline WideSigned<W>& operator%=(const WideInteger<W>& rhs)
                { *this = *this % rhs; return *this; }
            inline WideSigned<W> operator<<(unsigned rhs) const
                { return this->shift_left(rhs); }
            inline WideSigned<W> operator<<=(unsigned rhs)
                { *this = this->shift_left(rhs); return *this; }
            inline WideSigned<W> operator>>(unsigned rhs) const
                { return this->shift_right(rhs, this->sign_extend()); }
            inline WideSigned<W> operator>>=(unsigned rhs)
                { *this = *this >> rhs; return *this; }
            inline WideSigned<W> operator~() const
                { return this->bitwise_invert(); }
            inline WideSigned<W>& operator|=(const WideInteger<W>& rhs)
                { this->bitwise_or(rhs); return *this; }
            inline WideSigned<W>& operator&=(const WideInteger<W>& rhs)
                { this->bitwise_and(rhs); return *this; }
            inline WideSigned<W>& operator^=(const WideInteger<W>& rhs)
                { this->bitwise_xor(rhs); return *this; }
            inline WideSigned<W> operator|(const WideInteger<W>& rhs) const
                { WideInteger<W> tmp(*this); tmp.bitwise_or(rhs); return tmp; }
            inline WideSigned<W> operator&(const WideInteger<W>& rhs) const
                { WideInteger<W> tmp(*this); tmp.bitwise_and(rhs); return tmp; }
            inline WideSigned<W> operator^(const WideInteger<W>& rhs) const
                { WideInteger<W> tmp(*this); tmp.bitwise_xor(rhs); return tmp; }

            // Combined divide + modulo function.
            void divmod(const WideSigned<W>& rhs,
                WideSigned<W>& div, WideSigned<W>& mod) const
            {
                // Unsigned division on the absolute value of each input.
                satcat5::util::WideUnsigned<W> unum(this->abs());
                satcat5::util::WideUnsigned<W> urhs(rhs.abs());
                satcat5::util::WideUnsigned<W> udiv, umod;
                unum.divmod(urhs, udiv, umod);
                // Convert sign of outputs using the "x = d*y + m" identity.
                div = (is_negative() == rhs.is_negative()) ? udiv : -udiv;
                mod = is_negative() ? -umod : umod;
            }

            // Comparison operators.
            bool operator<(const WideSigned<W>& rhs) const {
                if (W == 0) return false;
                // Compare the most significant word as a signed integer.
                if ((s32)this->m_data[W-1] < (s32)rhs.m_data[W-1]) return true;
                if ((s32)this->m_data[W-1] > (s32)rhs.m_data[W-1]) return false;
                // Remaining words are compared as unsigned integers.
                for (unsigned a = W-2 ; a < UINT_MAX ; --a) {
                    if (this->m_data[a] < rhs.m_data[a]) return true;
                    if (this->m_data[a] > rhs.m_data[a]) return false;
                }
                return false;   // All fields equal.
            }
            bool operator>(const WideSigned<W>& rhs) const {
                if (W == 0) return false;
                // Compare the most significant word as a signed integer.
                if ((s32)this->m_data[W-1] > (s32)rhs.m_data[W-1]) return true;
                if ((s32)this->m_data[W-1] < (s32)rhs.m_data[W-1]) return false;
                // Remaining words are compared as unsigned integers.
                for (unsigned a = W-2 ; a < UINT_MAX ; --a) {
                    if (this->m_data[a] > rhs.m_data[a]) return true;
                    if (this->m_data[a] < rhs.m_data[a]) return false;
                }
                return false;   // All fields equal.
            }
            inline bool operator<=(const WideSigned<W>& rhs) const {
                return !operator>(rhs);
            }
            inline bool operator>=(const WideSigned<W>& rhs) const {
                return !operator<(rhs);
            }
        };

        // Template for unsigned integers.
        template <unsigned W> struct WideUnsigned final
            : public satcat5::util::WideInteger<W>
        {
        public:
            // Forward selected constructors.
            constexpr WideUnsigned()
                : satcat5::util::WideInteger<W>() {}
            constexpr explicit WideUnsigned<W>(u32 rhs)
                : satcat5::util::WideInteger<W>(rhs) {}
            constexpr explicit WideUnsigned<W>(u64 rhs)
                : satcat5::util::WideInteger<W>(rhs) {}
            constexpr WideUnsigned(u32 hi, u32 lo)
                : satcat5::util::WideInteger<W>(hi, lo) {}
            WideUnsigned(const satcat5::util::WideInteger<W>& rhs)
                { this->copy_from(rhs, 0); }
            WideUnsigned<W>& operator=(const WideInteger<W>& rhs)
                { this->copy_from(rhs, 0); return *this; }

            // Most arithmetic operations are thin wrappers.
            // Returned type always matches the first argument.
            WideUnsigned<W> operator-() const
                { WideUnsigned<W> tmp(~(*this)); ++tmp; return tmp; }
            inline WideUnsigned<W> operator+(const WideInteger<W>& rhs) const
                { return this->add(rhs); }
            inline WideUnsigned<W>& operator+=(const WideInteger<W>& rhs)
                { this->add_in_place(rhs); return *this; }
            inline WideUnsigned<W> operator-(const WideInteger<W>& rhs) const
                { return this->subtract(rhs); }
            inline WideUnsigned<W>& operator-=(const WideInteger<W>& rhs)
                { *this = this->subtract(rhs); return *this; }
            inline WideUnsigned<W> operator*(const WideInteger<W>& rhs) const
                { return this->multiply(rhs); }
            inline WideUnsigned<W>& operator*=(const WideInteger<W>& rhs)
                { *this = this->multiply(rhs); return *this; }
            inline WideUnsigned<W> operator/(const WideUnsigned<W>& rhs) const
                { WideUnsigned<W> d, m; this->divmod(rhs, d, m); return d; }
            inline WideUnsigned<W> operator%(const WideUnsigned<W>& rhs) const
                { WideUnsigned<W> d, m; this->divmod(rhs, d, m); return m; }
            inline WideUnsigned<W>& operator/=(const WideInteger<W>& rhs)
                { *this = *this / rhs; return *this; }
            inline WideUnsigned<W>& operator%=(const WideInteger<W>& rhs)
                { *this = *this % rhs; return *this; }
            inline WideUnsigned<W> operator<<(unsigned rhs) const
                { return this->shift_left(rhs); }
            inline WideUnsigned<W> operator<<=(unsigned rhs)
                { *this = this->shift_left(rhs); return *this; }
            inline WideUnsigned<W> operator>>(unsigned rhs) const
                { return this->shift_right(rhs, 0); }
            inline WideUnsigned<W> operator>>=(unsigned rhs)
                { *this = *this >> rhs; return *this; }
            inline WideUnsigned<W> operator~() const
                { return this->bitwise_invert(); }
            inline WideUnsigned<W>& operator|=(const WideInteger<W>& rhs)
                { this->bitwise_or(rhs); return *this; }
            inline WideUnsigned<W>& operator&=(const WideInteger<W>& rhs)
                { this->bitwise_and(rhs); return *this; }
            inline WideUnsigned<W>& operator^=(const WideInteger<W>& rhs)
                { this->bitwise_xor(rhs); return *this; }
            inline WideUnsigned<W> operator|(const WideInteger<W>& rhs) const
                { WideInteger<W> tmp(*this); tmp.bitwise_or(rhs); return tmp; }
            inline WideUnsigned<W> operator&(const WideInteger<W>& rhs) const
                { WideInteger<W> tmp(*this); tmp.bitwise_and(rhs); return tmp; }
            inline WideUnsigned<W> operator^(const WideInteger<W>& rhs) const
                { WideInteger<W> tmp(*this); tmp.bitwise_xor(rhs); return tmp; }

            // Combined divide + modulo function.
            void divmod(const WideUnsigned<W>& rhs,
                WideUnsigned<W>& div, WideUnsigned<W>& mod) const
            {
                // Shortcuts for unusual edge-cases.
                static constexpr WideUnsigned<W> ZERO(u32(0));
                static constexpr WideUnsigned<W> ONE(u32(1));
                if (rhs <= ONE)     {div = *this; mod = ZERO;  return;}
                if (*this == rhs)   {div = ONE;   mod = ZERO;  return;}
                if (*this < rhs)    {div = ZERO;  mod = *this; return;}
                // Order-of-magnitude estimate of the result.
                unsigned msb = 1 + this->msb() - rhs.msb();
                // Use the serial bit-at-a-time method.
                mod = *this; div = ZERO;
                for (unsigned b = msb ; b < UINT_MAX ; --b) {
                    WideUnsigned<W> tmp(rhs << b);
                    if (mod >= tmp) {
                        div.m_data[b/32] |= (1u << (b%32));
                        mod -= tmp;
                    }
                }
            }

            // Comparison operators.
            bool operator<(const WideUnsigned<W>& rhs) const {
                for (unsigned a = W-1 ; a < UINT_MAX ; --a) {
                    if (this->m_data[a] < rhs.m_data[a]) return true;
                    if (this->m_data[a] > rhs.m_data[a]) return false;
                }
                return false;   // All fields equal.
            }
            bool operator>(const WideUnsigned<W>& rhs) const {
                for (unsigned a = W-1 ; a < UINT_MAX ; --a) {
                    if (this->m_data[a] > rhs.m_data[a]) return true;
                    if (this->m_data[a] < rhs.m_data[a]) return false;
                }
                return false;   // All fields equal.
            }
            inline bool operator<=(const WideUnsigned<W>& rhs) const {
                return !operator>(rhs);
            }
            inline bool operator>=(const WideUnsigned<W>& rhs) const {
                return !operator<(rhs);
            }
        };

        // Shorthand for commonly used sizes.
        typedef satcat5::util::WideSigned<4> int128_t;
        typedef satcat5::util::WideSigned<8> int256_t;
        typedef satcat5::util::WideSigned<16> int512_t;
        typedef satcat5::util::WideUnsigned<4> uint128_t;
        typedef satcat5::util::WideUnsigned<8> uint256_t;
        typedef satcat5::util::WideUnsigned<16> uint512_t;

        // Shorthand for commonly used constants.
        constexpr satcat5::util::int128_t INT128_ZERO(u32(0));
        constexpr satcat5::util::int256_t INT256_ZERO(u32(0));
        constexpr satcat5::util::int512_t INT512_ZERO(u32(0));
        constexpr satcat5::util::int128_t INT128_ONE(u32(1));
        constexpr satcat5::util::int256_t INT256_ONE(u32(1));
        constexpr satcat5::util::int512_t INT512_ONE(u32(1));
        constexpr satcat5::util::uint128_t UINT128_ZERO(u32(0));
        constexpr satcat5::util::uint256_t UINT256_ZERO(u32(0));
        constexpr satcat5::util::uint512_t UINT512_ZERO(u32(0));
        constexpr satcat5::util::uint128_t UINT128_ONE(u32(1));
        constexpr satcat5::util::uint256_t UINT256_ONE(u32(1));
        constexpr satcat5::util::uint512_t UINT512_ONE(u32(1));
    }
}
