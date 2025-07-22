//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Implement the AES cipher in raw ECB mode.

#pragma once
#include <satcat5/types.h>

namespace satcat5 {
    namespace aes {
        //! Implement the AES cipher in raw ECB mode.
        //! The aes::Cipher class performs the AES encryption function, i.e.,
        //! encryption of 16-byte blocks in electronic-code-book (ECB) mode
        //! only. It supports 128-bit, 192-bit, and 256-bit keys.  ECB
        //! decryption is not supported.
        //!
        //! Given a key, the aes::Cipher object is initialized and performs key
        //! expansion. Then the encrypt() method can be used to generate a 16-byte
        //! ciphertext from a 16-byte plaintext. For example:
        //!
        //!```
        //!      u8 key[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
        //!      u8 pt[16] = {0};
        //!      u8 ct[16];
        //!      satcat5::aes::Cipher aes_core(key,128);
        //!      aes_core.encrypt(pt,ct);
        //!```
        //!
        //! Benchmarks: On a single Intel i7-10700 2.9 GHz processor with -O3
        //! optimization, performance is as follows:
        //! * AES-256: Ciphertext encryption:
        //!     * Throughput of 488.637268 Mbps.
        //!     * Total 47.478981 clock cycles per byte.
        //! * AES-192: Ciphertext encryption:
        //!     * Throughput of 570.453186 Mbps.
        //!     * Total 40.669419 clock cycles per byte.
        //! * AES-128: Ciphertext encryption:
        //!     * Throughput of 685.345886 Mbps.
        //!     * Total 33.851519 clock cycles per byte.
        //!
        //! LUTs are used for the GF multiplication and "sbox" functions, but
        //! the sub_bytes, row shifting, and column mixing are implemented using
        //! array manipulations. If increased throughput is desired, then these
        //! functions can be LUT'd, e.g. as in [openssl](https://www.openssl.org/)
        //! or replaced with hardware instructions.
        //!
        //! This implementation was derived from the
        //! [Tiny-AES library](https://github.com/kokke/tiny-AES-c/).
        //!
        //! The original Tiny-AES was published under the "Unlicense" license:
        //! ```
        //!      This is free and unencumbered software released into the public domain.
        //!      Anyone is free to copy, modify, publish, use, compile, sell, or
        //!      distribute this software, either in source code form or as a compiled
        //!      binary, for any purpose, commercial or non-commercial, and by any means.
        //! ```
        //! This derived work is released under the same license as the rest of SatCat5.
        class Cipher {
        public:
            //! Constructs an object for AES encryption using the specified key.
            //! Supported key sizes are 128, 192, or 256 bits.
            Cipher(const u8* key, unsigned key_size_bits);

            //! Encrypt exactly one block (16 bytes) of PlainText.
            void encrypt(const u8* plain, u8* cipher) const;

        protected:
            // state - array holding the intermediate results during decryption.
            typedef u8 state_t[4][4];

            // This function produces Nb(Nr+1) round keys.
            // The round keys are used in each round to decrypt the states.
            void key_expansion(const u8* key, unsigned key_size);

            // This function adds the round key to state.
            // The round key is added to the state by an XOR function.
            void add_round_key(u8 round, state_t* state) const;

            // The sub_bytes Function Substitutes the values in the
            // state matrix with values in an S-box.
            void sub_bytes(state_t* state) const;

            // The shift_rows() function shifts the rows in the state to the left.
            // Each row is shifted with different offset.
            // Offset = Row number. So the first row is not shifted.
            void shift_rows(state_t* state) const;

            // mix_columns function mixes the columns of the state matrix
            void mix_columns(state_t* state) const;

            u8 m_nr;
            u8 m_nk;
            u8 m_rnd_key[240];
        };
    }
}
