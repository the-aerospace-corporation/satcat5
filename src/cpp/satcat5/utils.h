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
// Miscellaneous mathematical utility functions
//
// Trivial functions are defined inline for performance optimization.
// All others are defined in "utils.cc".

#pragma once

#include <cstring>
#include <satcat5/types.h>

namespace satcat5 {
    namespace util {
        // Set or clear bit masks.
        inline void set_mask_u8(volatile u8& val, u8 mask)  {val |= mask;}
        inline void clr_mask_u8(volatile u8& val, u8 mask)  {val &= ~mask;}
        inline void set_mask_u8(u8& val, u8 mask)           {val |= mask;}
        inline void clr_mask_u8(u8& val, u8 mask)           {val &= ~mask;}
        inline void set_mask_u16(u16& val, u16 mask)        {val |= mask;}
        inline void clr_mask_u16(u16& val, u16 mask)        {val &= ~mask;}
        inline void set_mask_u32(u32& val, u32 mask)        {val |= mask;}
        inline void clr_mask_u32(u32& val, u32 mask)        {val &= ~mask;}

        inline void set_mask_if(u32& val, u32 mask, bool b) {
            if (b) set_mask_u32(val, mask);
            else   clr_mask_u32(val, mask);
        }

        // Min and max functions
        inline u8 min_u8(u8 a, u8 b)
            {return (a < b) ? a : b;}
        inline u16 min_u16(u16 a, u16 b)
            {return (a < b) ? a : b;}
        inline u32 min_u32(u32 a, u32 b)
            {return (a < b) ? a : b;}
        inline u64 min_u64(u64 a, u64 b)
            {return (a < b) ? a : b;}
        inline u32 min_s32(s32 a, s32 b)
            {return (a < b) ? a : b;}
        inline u64 min_s64(s64 a, s64 b)
            {return (a < b) ? a : b;}
        inline unsigned min_unsigned(unsigned a, unsigned b)
            {return (a < b) ? a : b;}

        inline u8 max_u8(u8 a, u8 b)
            {return (a > b) ? a : b;}
        inline u16 max_u16(u16 a, u16 b)
            {return (a > b) ? a : b;}
        inline u32 max_u32(u32 a, u32 b)
            {return (a > b) ? a : b;}
        inline u64 max_u64(u64 a, u64 b)
            {return (a > b) ? a : b;}
        inline u32 max_s32(s32 a, s32 b)
            {return (a > b) ? a : b;}
        inline u64 max_s64(s64 a, s64 b)
            {return (a > b) ? a : b;}
        inline unsigned max_unsigned(unsigned a, unsigned b)
            {return (a > b) ? a : b;}

        u32 max_u32(u32 a, u32 b, u32 c);

        // Absolute value
        inline u8 abs_s8(s8 a)
            {return (u8)((a < 0) ? -a : +a);}
        inline u16 abs_s16(s16 a)
            {return (u16)((a < 0) ? -a : +a);}
        inline u32 abs_s32(s32 a)
            {return (u32)((a < 0) ? -a : +a);}
        inline u64 abs_s64(s64 a)
            {return (u64)((a < 0) ? -a : +a);}

        // Square an input (and double output width)
        inline u32 square_u16(u16 x) {
            u32 xx = x;
            return (xx * xx);
        }
        inline u32 square_s16(s16 x) {
            u32 xx = (x < 0) ? -x : +x;
            return (xx * xx);
        }

        // Modulo addition: If A and B in range [0..M), return (A+B) % M
        // (Note: Assumes M <= UINT_MAX/2 for respective word size.)
        inline u16 modulo_add_u16(u16 sum, u16 m) {
            return (sum >= m) ? (sum - m) : sum;
        }
        inline u32 modulo_add_u32(u32 sum, u32 m) {
            return (sum >= m) ? (sum - m) : sum;
        }
        inline u32 modulo_add_u64(u64 sum, u64 m) {
            return (sum >= m) ? (sum - m) : sum;
        }
        inline unsigned modulo_add_uns(unsigned sum, unsigned m) {
            return (sum >= m) ? (sum - m) : sum;
        }

        // Integer division functions with various rounding options:
        template <typename T> inline T div_floor(T a, T b)
            {return a / b;}
        template <typename T> inline T div_round(T a, T b)
            {return (a + b/2) / b;}
        template <typename T> inline T div_ceil(T a, T b)
            {return (a + b-1) / b;}

        inline u32 div_floor_u32(u32 a, u32 b)  {return div_floor<u32>(a, b);}
        inline s32 div_floor_s32(s32 a, s32 b)  {return div_floor<s32>(a, b);};
        inline u32 div_round_u32(u32 a, u32 b)  {return div_round<u32>(a, b);};
        inline s32 div_round_s32(s32 a, s32 b)  {return div_round<s32>(a, b);};
        inline u32 div_ceil_u32 (u32 a, u32 b)  {return div_ceil<u32>(a, b);};
        inline s32 div_ceil_s32 (s32 a, s32 b)  {return div_ceil<s32>(a, b);};

        // Check if A is a multiple of B:
        bool is_multiple_u32(u32 a, u32 b);

        // XOR-reduction of all bits in a word:
        bool xor_reduce_u8(u8 x);
        bool xor_reduce_u16(u16 x);
        bool xor_reduce_u32(u32 x);
        bool xor_reduce_u64(u64 x);

        // Given X and Y, find the minimum N such that X * 2^N >= Y.
        unsigned min_2n(u32 x, u32 y);

        // Find integer square root y = floor(sqrt(x))
        u32 sqrt_u64(u64 x);
        u16 sqrt_u32(u32 x);
        u8  sqrt_u16(u16 x);

        // Extract fields from a big-endian byte array.
        u16 extract_be_u16(const u8* src);
        u32 extract_be_u32(const u8* src);

        // Store fields into a big-endian byte array.
        void write_be_u16(u8* dst, u16 val);
        void write_be_u32(u8* dst, u32 val);

        // Conversion function for I2C device addresses.
        // Natively, I2C device addresses are 7-bits followed by the read/write flag.
        // There are two common conventions for representing this in software:
        //  * 7-bit addresses (e.g., 0x77 = 1110111) are right-justified.
        //  * 8-bit addresses (e.g., 0xEE/0xEF = 1110111x) are left-justified
        //    and come in pairs, treating read and write as a "separate" address.
        struct I2cAddr {
        public:
            // Create I2C address from a 7-bit input (right-justified)
            static I2cAddr addr7(u8 addr);

            // Create I2C address from an 8-bit input (left-justified)
            static I2cAddr addr8(u8 addr);

            // Native internal representation for SatCat5.
            const u8 m_addr;

        private:
            explicit I2cAddr(u8 addr) : m_addr(addr) {}
        };

        // A simple class for tracking the record-holder for any unsigned
        // integer (e.g., elapsed microseconds, buffer size, etc.)
        class RunningMax {
        public:
            RunningMax();

            // Reset recorded maximum to zero.
            void clear();

            // Update stats if new value exceeds previous record.
            void update(const char* lbl, u32 value);

            // Parameters for the current record-holder.
            const char* m_label;    // Human-readable label
            u32 m_maximum;          // Maximum observed value
        };

        // Cross-platform determination of native byte-order.
        // https://stackoverflow.com/questions/2100331/c-macro-definition-to-determine-big-endian-or-little-endian-machine
        enum {SATCAT5_LITTLE_ENDIAN = 0x03020100ul, SATCAT5_BIG_ENDIAN = 0x00010203ul};
        constexpr union {u8 bytes[4]; u32 value;} HOST_ORDER_CANARY = {{0,1,2,3}};
        inline u32 HOST_BYTE_ORDER() {return HOST_ORDER_CANARY.value;}

        // In-place byte-for-byte format conversion, aka "type-punning".
        template<typename T1, typename T2> inline T2 reinterpret(T1 x)
        {
            static_assert(sizeof(T1) == sizeof(T2), "Type size mismatch");
            // Note: Using "memcpy" for type-punning is preferred safe-ish method.
            // Most compilers will optimize this to a no-op, as desired.  See also:
            //  https://gist.github.com/shafik/848ae25ee209f698763cffee272a58f8
            //  https://stackoverflow.com/questions/48803363/bitwise-casting-uint32-t-to-float-in-c-c
            T2 y;
            std::memcpy(&y, &x, sizeof(T1));
            return y;
        }
    }
}
