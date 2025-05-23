//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
        template<typename T>
        inline void clr_mask(T& val, T mask)                {val &= ~mask;}
        template<typename T>
        inline void set_mask(T& val, T mask)                {val |= mask;}

        template<typename T>
        inline void set_mask_if(T& val, T mask, bool b) {
            if (b) set_mask<T>(val, mask);
            else   clr_mask<T>(val, mask);
        }

        // Return a bit-mask where the N LSBs are set.
        template <typename T> inline constexpr T mask_lower(unsigned n) {
            return ((n >= 8*sizeof(T)) ? 0 : (T(1) << n)) - 1;
        }

        // Basic implementation of an std::optional equivalent compatible with
        // C++11. ONLY for use by basic types with trivial default constructors
        // and destructors.
        // https://www.club.cc.cmu.edu/%7Eajo/disseminate/2017-02-15-Optional-From-Scratch.pdf
        template <typename T>
        struct optional {
            optional() : val_(), has_val_(false) {}
            optional(const T& t) : val_(t), has_val_(true) {} // NOLINT
            inline void reset() { has_val_ = false; }
            inline optional& operator=(const T& t)
                { val_ = t; has_val_ = true; return *this; }
            inline T value() const { return val_; }
            inline T value_or(const T& t) const { return has_val_ ? val_ : t; }
            inline bool has_value() const { return has_val_; }
            inline explicit operator bool() const { return has_val_; }
        private:
            T val_; bool has_val_;
        };

        // Min and max functions
        inline constexpr u8 min_u8(u8 a, u8 b)
            {return (a < b) ? a : b;}
        inline constexpr u16 min_u16(u16 a, u16 b)
            {return (a < b) ? a : b;}
        inline constexpr u32 min_u32(u32 a, u32 b)
            {return (a < b) ? a : b;}
        inline constexpr u64 min_u64(u64 a, u64 b)
            {return (a < b) ? a : b;}
        inline constexpr u32 min_s32(s32 a, s32 b)
            {return (a < b) ? a : b;}
        inline constexpr u64 min_s64(s64 a, s64 b)
            {return (a < b) ? a : b;}
        inline constexpr unsigned min_unsigned(unsigned a, unsigned b)
            {return (a < b) ? a : b;}

        inline constexpr u8 max_u8(u8 a, u8 b)
            {return (a > b) ? a : b;}
        inline constexpr u16 max_u16(u16 a, u16 b)
            {return (a > b) ? a : b;}
        inline constexpr u32 max_u32(u32 a, u32 b)
            {return (a > b) ? a : b;}
        inline constexpr u64 max_u64(u64 a, u64 b)
            {return (a > b) ? a : b;}
        inline constexpr u32 max_s32(s32 a, s32 b)
            {return (a > b) ? a : b;}
        inline constexpr u64 max_s64(s64 a, s64 b)
            {return (a > b) ? a : b;}
        inline constexpr unsigned max_unsigned(unsigned a, unsigned b)
            {return (a > b) ? a : b;}

        u32 max_u32(u32 a, u32 b, u32 c);

        // For an input x, the "clamp" function limits the output range to +/- y.
        // i.e., if abs(x) <= y then clamp(x) => x, else clamp(x) => sign(x)*y
        template <typename T> inline constexpr T clamp(T x, T y) {
            return (x < -y) ? -y : (x > y ? y : x);
        }

        // Absolute value
        inline constexpr u8 abs_s8(s8 a)
            {return (u8)((a < 0) ? -a : +a);}
        inline constexpr u16 abs_s16(s16 a)
            {return (u16)((a < 0) ? -a : +a);}
        inline constexpr u32 abs_s32(s32 a)
            {return (u32)((a < 0) ? -a : +a);}
        inline constexpr u64 abs_s64(s64 a)
            {return (u64)((a < 0) ? -a : +a);}

        // Sign function (-x/0/+x -> -1/0/+1)
        template <typename T> inline constexpr T sign(T x) {
            return T((x < 0) ? -1 : (x > 0 ? 1 : 0));
        }

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
        inline constexpr u16 modulo_add_u16(u16 sum, u16 m) {
            return (sum >= m) ? (sum - m) : sum;
        }
        inline constexpr u32 modulo_add_u32(u32 sum, u32 m) {
            return (sum >= m) ? (sum - m) : sum;
        }
        inline constexpr u32 modulo_add_u64(u64 sum, u64 m) {
            return (sum >= m) ? (sum - m) : sum;
        }
        inline constexpr unsigned modulo_add_uns(unsigned sum, unsigned m) {
            return (sum >= m) ? (sum - m) : sum;
        }

        // Portability wrapper for platforms with signed division and modulo:
        //  * Modulo always returns the positive equivalent:
        //      modulo(-7, 4) = +1
        //      modulo(-6, 4) = +2
        //      modulo(-5, 4) = +3
        //      modulo(-4, 4) =  0
        //  * Divide always rounds toward -infinity:
        //      divide(-7, 4) = -2
        //      divide(-6, 4) = -2
        //      divide(-5, 4) = -2
        //      divide(-4, 4) = -1
        // https://stackoverflow.com/questions/10023440/signed-division-in-c
        template <typename T> inline constexpr T divide(T a, T b) {
            return (a % b < 0) ? (a / b - 1) : (a / b);
        }
        template <typename T> inline constexpr T modulo(T a, T b) {
            return (a % b < 0) ? (a % b + b) : (a % b);
        }

        // Calculate log2(x), rounding up or down.
        template <typename T> unsigned log2_ceil(T x) {
            unsigned count = 0;
            while (x > 1) { ++count; x = (x+1)/2; }
            return count;
        }

        template <typename T> unsigned log2_floor(T x) {
            unsigned count = 0;
            while (x > 1) { ++count; x /= 2; }
            return count;
        }

        // Round a floating-point value to the nearest integer.
        // Behavior at the boundary is indeterminate (e.g., 1.5 -> 1 or 2).
        // Note: The round() in <cmath> isn't always marked as constexpr.
        template <typename T> inline constexpr s64 round_s64(T x) {
            return static_cast<s64>(x + (T)(x < 0 ? -0.5 : 0.5));
        }
        template <typename T> inline constexpr u64 round_u64(T x) {
            return static_cast<u64>(x + (T)0.5);
        }

        // Variant of "round_u64" that returns zero if input is out of range.
        template <typename T> inline constexpr u64 round_s64z(T x) {
            return (T(INT64_MIN) < x && x < T(INT64_MAX)) ? satcat5::util::round_s64(x) : 0;
        }
        template <typename T> inline constexpr u64 round_u64z(T x) {
            return (x < T(UINT64_MAX)) ? satcat5::util::round_u64(x) : 0;
        }

        // Unsigned add with saturation: min(A + B, C)
        // If "C" is not specified, default to maximum representable value.
        // (i.e., UINT32_MAX, UINT64_MAX, etc., equal to 2^N - 1.)
        // This operation is nontrivial due to handling of integer overflow.
        // This function is NOT suitable for use with signed integers.
        template <typename T>
        inline constexpr T saturate_add(T a, T b, T c = T(-1)) {
            return (a + b < c && a + b >= a) ? (a + b) : (c);
        }

        // Calculate 2^N for very large N, returning a double.
        constexpr double pow2d(unsigned n) {
            return (n < 64) ? (double(1ull << n)) : (double(1ull << 63) * pow2d(n-63));
        }

        // Integer division functions with various rounding options:
        template <typename T> inline constexpr T div_floor(T a, T b)
            {return divide<T>(a, b);}
        template <typename T> inline constexpr T div_round(T a, T b)
            {return divide<T>(a + b/2, b);}
        template <typename T> inline constexpr T div_ceil(T a, T b)
            {return divide<T>(a + b-1, b);}

        inline constexpr u32 div_floor_u32(u32 a, u32 b)
            {return div_floor<u32>(a, b);}
        inline constexpr s32 div_floor_s32(s32 a, s32 b)
            {return div_floor<s32>(a, b);};
        inline constexpr u32 div_round_u32(u32 a, u32 b)
            {return div_round<u32>(a, b);};
        inline constexpr s32 div_round_s32(s32 a, s32 b)
            {return div_round<s32>(a, b);};
        inline constexpr u32 div_ceil_u32 (u32 a, u32 b)
            {return div_ceil<u32>(a, b);};
        inline constexpr s32 div_ceil_s32 (s32 a, s32 b)
            {return div_ceil<s32>(a, b);};

        // Check if A is a multiple of B:
        bool is_multiple_u32(u32 a, u32 b);

        // Count the number of '1' bits in an integer.
        unsigned popcount(u32 x);

        // Reverse the order of bytes in an integer.
        inline constexpr u64 reverse_bytes_u64(u64 num) {
            return ((num & 0xFF00000000000000ull) >> 56)
                 | ((num & 0x00FF000000000000ull) >> 40)
                 | ((num & 0x0000FF0000000000ull) >> 24)
                 | ((num & 0x000000FF00000000ull) >> 8)
                 | ((num & 0x00000000FF000000ull) << 8)
                 | ((num & 0x0000000000FF0000ull) << 24)
                 | ((num & 0x000000000000FF00ull) << 40)
                 | ((num & 0x00000000000000FFull) << 56);
        }

        inline constexpr u32 reverse_bytes_u32(u32 num) {
            return ((num & 0xFF000000u) >> 24)
                 | ((num & 0x00FF0000u) >> 8)
                 | ((num & 0x0000FF00u) << 8)
                 | ((num & 0x000000FFu) << 24);
        }

        inline constexpr u16 reverse_bytes_u16(u16 num) {
            return ((num & 0xFF00u) >> 8) | ((num & 0x00FFu) << 8);
        }

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
        u64 extract_be_u64(const u8* src);

        // Store fields into a big-endian byte array.
        void write_be_u16(u8* dst, u16 val);
        void write_be_u32(u8* dst, u32 val);
        void write_be_u64(u8* dst, u64 val);

        // Swap two values using a temporary variable.
        template <typename T> void swap_ptr(T* x, T* y) {
            if (x != y) {T z = *x; *x = *y; *y = z;}
        }
        template <typename T> void swap_ref(T& x, T& y) {
            if (x != y) {T z = x; x = y; y = z;}
        }

        // Templated in-place stable sort for small arrays.
        // Slower than std::sort(...) but does not require heap allocation.
        template <typename T> void sort(T* begin, T* end) {
            // Using selection-sort for simplicity, O(N^2).
            for (T* a = begin ; a+1 != end ; ++a) {
                T* min_ptr = a;
                for (T* b = a+1 ; b != end ; ++b) {
                    if (*b < *min_ptr) min_ptr = b;
                }
                satcat5::util::swap_ptr(a, min_ptr);
            }
        }

        // Simple cross-platform psuedorandom number generator (PRNG).
        // Generates uniform psuedorandom integer outputs.
        class Prng final {
        public:
            explicit constexpr Prng(u64 seed = 123456789ull)
                : m_state(seed) {}
            u32 next();                     // Range [0..2^32)
            u32 next(u32 mn, u32 mx);       // Range [mn..mx]
            inline void seed(u64 seed) {m_state = seed;}
        protected:
            u64 m_state;
        };

        // Global instance of the Prng class, above.
        extern satcat5::util::Prng prng;

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
        // https://stackoverflow.com/questions/2100331/
        enum {SATCAT5_LITTLE_ENDIAN = 0x03020100ul, SATCAT5_BIG_ENDIAN = 0x00010203ul};
        constexpr union {u8 bytes[4]; u32 value;} HOST_ORDER_CANARY = {{0,1,2,3}};
        inline constexpr u32 HOST_BYTE_ORDER() {return HOST_ORDER_CANARY.value;}

        // In-place byte-for-byte format conversion, aka "type-punning".
        template<typename T1, typename T2> inline T2 reinterpret(T1 x) {
            static_assert(sizeof(T1) == sizeof(T2), "Type size mismatch");
            // Note: Using "memcpy" for type-punning is preferred safe-ish method.
            // Most compilers will optimize this to a no-op, as desired.  See also:
            //  https://gist.github.com/shafik/848ae25ee209f698763cffee272a58f8
            //  https://stackoverflow.com/questions/48803363/
            T2 y;
            std::memcpy(&y, &x, sizeof(T1));
            return y;
        }
    }
}
