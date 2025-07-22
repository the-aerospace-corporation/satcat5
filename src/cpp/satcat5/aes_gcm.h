//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Implement the AES cipher in Galois/Counter Mode (GCM).

#pragma once
#include <satcat5/aes_cipher.h>

// Enable fast lookup table for the Galois-field multiply operation?
// This yields a massive speed boost, but consumes 64 kiB of memory.
#ifndef SATCAT5_GCM_FAST
#define SATCAT5_GCM_FAST 1
#endif

namespace satcat5 {
    namespace aes {
        //! Implement the AES cipher in Galois/Counter Mode (GCM).
        //! The aes::Gcm class performs AES-GCM encryption and decryption on
        //! blocks of data.  The aes::Gcm object is initialized with a key and
        //! an IV.  Then the `encrypt_decrypt` function can be used to generate
        //! ciphertext from a arbitrary-length plaintext (pt), and the
        //! `compute_tag` method generates a 16-byte authentication tag from
        //! arbitrary-length plaintext and additional data (aad).
        //!
        //! Because encryption and decryption are the same operation, a single
        //! function is used for both. Example usage:
        //!
        //!```
        //!      u8 key[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
        //!      u8 iv[12]  = {0,1,2,3,4,5,6,7,8,9,10,11};
        //!      u8 pt[1000] = {0};
        //!      u8 aad[30]  = {1};
        //!      u8 ct[1000];
        //!      u8 tag[16];
        //!      satcat5::aes::Gcm gcm_encrypter(128, key, 96, iv);
        //!      gcm_encrypter.gcm_encrypt_decrypt(1000, pt, ct);
        //!      gcm_encrypter.gcm_compute_tag(30, 1000, aad, ct, tag);
        //!      // ct and tag now contain the ciphertext and authentication tag, respectively.
        //!```
        //!
        //! Continuing the example, we use a second aes::Gcm object to perform
        //! decryption. (Otherwise, the internal counter will be incorrect):
        //!
        //!```
        //!      satcat5::aes::Gcm gcm_decrypter(128, key, 96, iv);
        //!      u8 decrypted_text[1000];
        //!      gcm_decrypter.gcm_encrypt_decrypt(1000, ct, decrypted_text);
        //!      // decrypted_text should match the original plaintext.
        //!```
        //!
        //! AES-GCM performs AES encryption on an internal 16-byte counter, then
        //! XORs each encrypted counter block with the pt to generate the ct
        //! (rather than performing AES directly on the ct).  As a result, the
        //! encrypter's and decrypter's internal counters must agree to correctly
        //! recover the pt. The counter is initialized with a nonce/IV (which is
        //! also used in the authenication tag), then incremented after each
        //! 16-byte pt block.
        //!
        //! The GCM encrypt/decrypt algorithm has minimal overhead, and its
        //! performance is largely dependent on the AES cipher performance. The
        //! GF(2^128) multiply is done using a LUT, which results in ~2 clock
        //! cycles per byte (text + AAD) for authentication tag generation.
        //!
        //! Benchmarks: On a single Intel i7-10700 2.9 GHz processor with -O3
        //! optimization, performance is as follows:
        //! * GCM-AES-256 encryption+tag generation:
        //!     * Throughput of 466.907898 Mbps.
        //!     * 49.688600 clock cycles per byte.
        //! * GCM-AES-192 encryption+tag generation:
        //!     * Throughput of 543.662903 Mbps.
        //!     * 42.673500 clock cycles per byte.
        //! * GCM-AES-128 encryption+tag generation:
        //!     * Throughput of 647.615967 Mbps.
        //!     * 35.823700 clock cycles per byte.
        class Gcm {
        public:
            //! Constructor needs key and iv
            Gcm(unsigned key_length_bits, const u8* in_key,
                unsigned iv_length_bits,  const u8* in_iv);

            //! Reset the counter and e_y_0 with a new IV.
            //! e.g. incrementing the packet number in MACsec
            bool set_iv(unsigned iv_length_bits, const u8* new_iv);

            //! XOR src with the AES-GCM cipher into dest.
            //! Note encrypt and decrypt are the same operation.
            void encrypt_decrypt(unsigned text_len_bytes, const u8* src, u8* dst);

            //! Use ciphertext and additional authenticated data (AAD) to
            //! generate an authentication tag.
            void compute_tag(unsigned aad_len_bytes, unsigned text_len_bytes,
                const u8* aad, const u8 *ct, u8 tag[16]);

        protected:
            void mult_by_h(const u8* src, u8* dest);
            void increment_counter();
            void gf_128_mult(const u8* src_1, const u8* src_2, u8* dest);

            satcat5::aes::Cipher m_aes;
            u8 m_ctr[16];
            u8 m_h[16];
            u8 m_ey0[16];
            #if SATCAT5_GCM_FAST
            u8 m_hlut[16][256][16]; // 64 kiB lookup table
            #endif
        };
    }
}
