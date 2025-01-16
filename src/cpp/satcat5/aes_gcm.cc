//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cstring>
#include <satcat5/aes_gcm.h>
#include <satcat5/utils.h>

using satcat5::aes::Cipher;
using satcat5::aes::Gcm;
using satcat5::util::write_be_u64;

//constructor needs key and iv. The Gcm object can encrypt/decrypt and generate an authentication tag from CT and AAD.
Gcm::Gcm(unsigned key_length_bits,  const u8* in_key,
         unsigned iv_length_bits,   const u8* in_iv)
    : m_aes(in_key, key_length_bits)
    , m_ctr{}, m_h{}, m_ey0{}
{
    // initialize GCM variables
    memset(m_h, 0, 16*sizeof(u8));
    memset(m_ctr, 0, 16*sizeof(u8));
    m_aes.encrypt(m_ctr, m_h);
#if SATCAT5_GCM_FAST
    // populate H-matrix lookup table
    u8 val[16] = {0};
    for (unsigned i = 0; i < 16; ++i) {
        for (unsigned j = 0; j < 256; ++j) {
            val[i] = j;
            gf_128_mult(m_h, val, m_hlut[i][j]);
        }
        val[i] = 0;
    }
#endif
    // initialize the counter with the IV
    if (in_iv) set_iv(iv_length_bits, in_iv);
}

// reset the counter and m_ey0 with a new IV.
// This is done when incrementing the packet number in MACsec
bool Gcm::set_iv(unsigned iv_length_bits, const u8* new_iv) {
    memset(m_ctr, 0, 16);
    if (iv_length_bits == 96) {
        memcpy(m_ctr, new_iv, 12);
        increment_counter();
    } else {
        unsigned iv_length_bytes = (iv_length_bits + 7) / 8;
        unsigned iv_length_blocks = (iv_length_bytes + 15) / 16;
        for (unsigned i = 0; i < iv_length_blocks; ++i) {
            for (unsigned j = 0; j < 16 && (16*i + j) < iv_length_bytes; ++j)
                m_ctr[j] ^= new_iv[16*i + j];
            mult_by_h(m_ctr, m_ctr);
        }
        u8 len_str[16] = {0};
        write_be_u64(len_str + 8, iv_length_bits);
        for (unsigned j = 0; j < 16; ++j)
            m_ctr[j] ^= len_str[j];
        mult_by_h(m_ctr, m_ctr);
    }
    m_aes.encrypt(m_ctr, m_ey0);
    return true;
}

// GCM does not run the pt through AES encryption,
// rather it encrypts a 16-byte counter,
// then XORs the PT with the encrypted counter,
// so encrypt and decrypt are the same operation.
void Gcm::encrypt_decrypt(unsigned text_len_bytes, const u8* src, u8* dst) {
    unsigned num_text_blocks = (text_len_bytes + 15) /  16;
    u8 e_y_i[16]  = {0};
    for (unsigned i = 0; i < num_text_blocks; ++i) {
        increment_counter();
        m_aes.encrypt(m_ctr, e_y_i);
        for (unsigned j = 0; j < 16 && (i * 16 + j) < text_len_bytes; ++j)
            dst[i * 16 + j] = src[i * 16 + j] ^ e_y_i[j];
    }
}

// use ciphertext and additional authenticated data to generate an authentication tag
void Gcm::compute_tag(
    unsigned aad_len_bytes, unsigned txt_len_bytes,
    const u8* aad, const u8 *ct, u8 tag[16])
{
    unsigned num_txt_blocks = (txt_len_bytes + 15) /  16;
    unsigned num_aad_blocks = (aad_len_bytes + 15) /  16;
    u8 hash[16] = {0};
    u8 len_str[16];
    for (unsigned i = 0; i < num_aad_blocks; ++i) {
        for (unsigned j = 0; j < 16 && (j + 16 * i) < aad_len_bytes; ++j)
            hash[j] ^= aad[j + i * 16];
        mult_by_h(hash, hash);
    }
    for (unsigned i = 0; i < num_txt_blocks; ++i) {
        for (unsigned j = 0; j < 16 && (j + 16 * i) < txt_len_bytes; ++j)
            hash[j] ^= ct[i * 16 + j];
        mult_by_h(hash, hash);
    }
    write_be_u64(len_str + 0, aad_len_bytes * 8);   // len(A)
    write_be_u64(len_str + 8, txt_len_bytes * 8);   // len(C)
    for (unsigned j = 0; j < 16; ++j)
        hash[j] ^= len_str[j];
    mult_by_h(hash, hash);
    for (unsigned j = 0; j < 16; ++j)
        tag[j] = hash[j] ^ m_ey0[j];
}

// either uses a LUT to perform GF(2^128) multiplication by H
// or direct computation with gf_128_mult
void Gcm::mult_by_h(const u8* src, u8* dest) {
    u8 src_cpy[16]; // to allow src = dest
    memcpy(src_cpy, src,16);
#if SATCAT5_GCM_FAST
    // Use the precalculated lookup table?
    for (unsigned i = 0; i < 16; ++i) {
        dest[i] = 0;
        for (unsigned j = 0; j < 16; ++j)
            dest[i] ^= m_hlut[j][src_cpy[j]][i];
    }
#else
    // Direct calculation uses less memory.
    gf_128_mult(src_cpy, m_h, dest);
#endif
}

// The counter is effectively a 128-bit unsigned, stored MSB-first.
// Increment the counter by 1. This is called very frequently.
void Gcm::increment_counter() {
    for (int j = 15; j >= 0; j--)
        if (++m_ctr[j]) break;
}

// performs multiplication of two u8[16]s in GF(2^128)
// also used to populate the LUT, since the multiplication operation is fairly expensive
void Gcm::gf_128_mult(const u8* src_1, const u8* src_2, u8* dest) {
    u8 v[16], u[16];
    u8 rem = 0xE1;
    unsigned i, j, k;
    memcpy(u, src_1, 16);
    memcpy(v, src_2, 16);
    memset(dest, 0, 16);
    for (i = 0; i < 16; ++i) {
        for (j = 0; j < 8; ++j) {
            if (u[i] & (0x80 >> j)) {
                for (k = 0; k < 16; ++k)
                    dest[k] ^= v[k];
            }
            if (v[15] & 0x01) {
                for (k = 15; k >= 1; k--) {
                    v[k] = v[k] >> 1;
                    if (v[k - 1] & 0x01)
                        v[k] |= 0x80;
                }
                v[0] = v[0] >> 1;
                v[0] ^= rem;
            } else {
                for (k = 15; k >= 1; k--) {
                    v[k] = v[k] >> 1;
                    if (v[k - 1] & 0x01)
                        v[k] |= 0x80;
                }
                v[0] = v[0] >> 1;
            }
        }
    }
}
