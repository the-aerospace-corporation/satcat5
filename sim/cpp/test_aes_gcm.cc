//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test our AES-GCM block using the NIST test cases:
// https://csrc.nist.rip/groups/ST/toolkit/BCM/documents/proposedmodes/gcm/gcm-spec.pdf

#include <cstring>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/aes_gcm.h>

// Define some constants used in many different test cases.
static const u8 k_0[64] = { 0 };
static const u8 p_0[1024] = { 0 };
static const u8 nonce_0[12] = { 0 };

static const u8 k_1[16] =
    { 0xfe,0xff,0xe9,0x92,0x86,0x65,0x73,0x1c,0x6d,0x6a,0x8f,0x94,0x67,0x30,0x83,0x08 };
static const u8 p_1[64] = {
    0xd9,0x31,0x32,0x25,0xf8,0x84,0x06,0xe5,0xa5,0x59,0x09,0xc5,0xaf,0xf5,0x26,0x9a,
    0x86,0xa7,0xa9,0x53,0x15,0x34,0xf7,0xda,0x2e,0x4c,0x30,0x3d,0x8a,0x31,0x8a,0x72,
    0x1c,0x3c,0x0c,0x95,0x95,0x68,0x09,0x53,0x2f,0xcf,0x0e,0x24,0x49,0xa6,0xb5,0x25,
    0xb1,0x6a,0xed,0xf5,0xaa,0x0d,0xe6,0x57,0xba,0x63,0x7b,0x39,0x1a,0xaf,0xd2,0x55 };
static const u8 nonce_1[12] =
    {0xca,0xfe,0xba,0xbe,0xfa,0xce,0xdb,0xad,0xde,0xca,0xf8,0x88};
static const u8 nonce_2[60] = {
    0x93,0x13,0x22,0x5d,0xf8,0x84,0x06,0xe5,0x55,0x90,0x9c,0x5a,0xff,0x52,0x69,0xaa,
    0x6a,0x7a,0x95,0x38,0x53,0x4f,0x7d,0xa1,0xe4,0xc3,0x03,0xd2,0xa3,0x18,0xa7,0x28,
    0xc3,0xc0,0xc9,0x51,0x56,0x80,0x95,0x39,0xfc,0xf0,0xe2,0x42,0x9a,0x6b,0x52,0x54,
    0x16,0xae,0xdb,0xf5,0xa0,0xde,0x6a,0x57,0xa6,0x37,0xb3,0x9b};
static const u8 aad_1[20] =
    { 0xfe, 0xed,0xfa,0xce,0xde,0xad,0xbe,0xef,0xfe,0xed,0xfa,0xce,0xde,0xad,0xbe,0xef,0xab,0xad,0xda,0xd2 };

static const u8 k_2[32] = {     // Two consecutive copies of K_1
    0xfe,0xff,0xe9,0x92,0x86,0x65,0x73,0x1c,0x6d,0x6a,0x8f,0x94,0x67,0x30,0x83,0x08,
    0xfe,0xff,0xe9,0x92,0x86,0x65,0x73,0x1c,0x6d,0x6a,0x8f,0x94,0x67,0x30,0x83,0x08 };


TEST_CASE("AES-GCM NIST Test Vectors") {
    SATCAT5_TEST_START;
    u8 c[1024] = {0};
    u8 t[16] = {0};
    // --------------------------------------
    SECTION("Test Case 1") {
        const u8 exp_t[16] = {0x58,0xE2,0xFC,0xCE,0xFA,0x7E,0x30,0x61,0x36,0x7F,0x1D,0x57,0xA4,0xE7,0x45,0x5A};
        satcat5::aes::Gcm gcm(128,k_0,96,nonce_0);
        gcm.encrypt_decrypt(0,p_0,c);
        gcm.compute_tag(0,0,NULL,c,t);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 2") {
        const u8 exp_c[16] = {0x03,0x88,0xDA,0xCE,0x60,0xB6,0xA3,0x92,0xF3,0x28,0xC2,0xB9,0x71,0xB2,0xFE,0x78};
        const u8 exp_t[16] = {0xAB,0x6E,0x47,0xD4,0x2C,0xEC,0x13,0xBD,0xF5,0x3A,0x67,0xB2,0x12,0x57,0xBD,0xDF};
        satcat5::aes::Gcm gcm(128,k_0,96,nonce_0);
        gcm.encrypt_decrypt(16,p_0,c);
        gcm.compute_tag(0,16,NULL,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 3") {
        const u8 exp_c[64] = {
            0x42,0x83,0x1E,0xC2,0x21,0x77,0x74,0x24,0x4B,0x72,0x21,0xB7,0x84,0xD0,0xD4,0x9C,
            0xE3,0xAA,0x21,0x2F,0x2C,0x02,0xA4,0xE0,0x35,0xC1,0x7E,0x23,0x29,0xAC,0xA1,0x2E,
            0x21,0xD5,0x14,0xB2,0x54,0x66,0x93,0x1C,0x7D,0x8F,0x6A,0x5A,0xAC,0x84,0xAA,0x05,
            0x1B,0xA3,0x0B,0x39,0x6A,0x0A,0xAC,0x97,0x3D,0x58,0xE0,0x91,0x47,0x3F,0x59,0x85};
        const u8 exp_t[16] = {
            0x4D,0x5C,0x2A,0xF3,0x27,0xCD,0x64,0xA6,0x2C,0xF3,0x5A,0xBD,0x2B,0xA6,0xFA,0xB4};
        satcat5::aes::Gcm gcm(128,k_1,96,nonce_1);
        gcm.encrypt_decrypt(64,p_1,c);
        gcm.compute_tag(0,64,NULL,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 4") {
        const u8 exp_c[60] = {
            0x42,0x83,0x1E,0xC2,0x21,0x77,0x74,0x24,0x4B,0x72,0x21,0xB7,0x84,0xD0,0xD4,0x9C,
            0xE3,0xAA,0x21,0x2F,0x2C,0x02,0xA4,0xE0,0x35,0xC1,0x7E,0x23,0x29,0xAC,0xA1,0x2E,
            0x21,0xD5,0x14,0xB2,0x54,0x66,0x93,0x1C,0x7D,0x8F,0x6A,0x5A,0xAC,0x84,0xAA,0x05,
            0x1B,0xA3,0x0B,0x39,0x6A,0x0A,0xAC,0x97,0x3D,0x58,0xE0,0x91};
        const u8 exp_t[16] = {
            0x5B,0xC9,0x4F,0xBC,0x32,0x21,0xA5,0xDB,0x94,0xFA,0xE9,0x5A,0xE7,0x12,0x1A,0x47};
        satcat5::aes::Gcm gcm(128,k_1,96,nonce_1);
        gcm.encrypt_decrypt(60,p_1,c);
        gcm.compute_tag(20,60,aad_1,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 5") {
        const u8 exp_c[60] = {
            0x61,0x35,0x3b,0x4c,0x28,0x06,0x93,0x4a,0x77,0x7f,0xf5,0x1f,0xa2,0x2a,0x47,0x55,
            0x69,0x9b,0x2a,0x71,0x4f,0xcd,0xc6,0xf8,0x37,0x66,0xe5,0xf9,0x7b,0x6c,0x74,0x23,
            0x73,0x80,0x69,0x00,0xe4,0x9f,0x24,0xb2,0x2b,0x09,0x75,0x44,0xd4,0x89,0x6b,0x42,
            0x49,0x89,0xb5,0xe1,0xeb,0xac,0x0f,0x07,0xc2,0x3f,0x45,0x98};
        const u8 exp_t[16] = {
            0x36,0x12,0xd2,0xe7,0x9e,0x3b,0x07,0x85,0x56,0x1b,0xe1,0x4a,0xac,0xa2,0xfc,0xcb};
        satcat5::aes::Gcm gcm(128,k_1,64,nonce_1);
        gcm.encrypt_decrypt(60,p_1,c);
        gcm.compute_tag(20,60,aad_1,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 6") {
        const u8 exp_c[60] = {
            0x8c,0xe2,0x49,0x98,0x62,0x56,0x15,0xb6,0x03,0xa0,0x33,0xac,0xa1,0x3f,0xb8,0x94,
            0xbe,0x91,0x12,0xa5,0xc3,0xa2,0x11,0xa8,0xba,0x26,0x2a,0x3c,0xca,0x7e,0x2c,0xa7,
            0x01,0xe4,0xa9,0xa4,0xfb,0xa4,0x3c,0x90,0xcc,0xdc,0xb2,0x81,0xd4,0x8c,0x7c,0x6f,
            0xd6,0x28,0x75,0xd2,0xac,0xa4,0x17,0x03,0x4c,0x34,0xae,0xe5};
        const u8 exp_t[16] = {
            0x61,0x9c,0xc5,0xae,0xff,0xfe,0x0b,0xfa,0x46,0x2a,0xf4,0x3c,0x16,0x99,0xd0,0x50};
        satcat5::aes::Gcm gcm(128,k_1,480,nonce_2);
        gcm.encrypt_decrypt(60,p_1,c);
        gcm.compute_tag(20,60,aad_1,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 7") {
        const u8 exp_t[16] = {0xcd,0x33,0xb2,0x8a,0xc7,0x73,0xf7,0x4b,0xa0,0x0e,0xd1,0xf3,0x12,0x57,0x24,0x35};
        satcat5::aes::Gcm gcm(192,k_0,96,nonce_0);
        gcm.encrypt_decrypt(0,p_0,c);
        gcm.compute_tag(0,0,NULL,c,t);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 8") {
        const u8 exp_c[16] = {0x98,0xe7,0x24,0x7c,0x07,0xf0,0xfe,0x41,0x1c,0x26,0x7e,0x43,0x84,0xb0,0xf6,0x00};
        const u8 exp_t[16] = {0x2f,0xf5,0x8d,0x80,0x03,0x39,0x27,0xab,0x8e,0xf4,0xd4,0x58,0x75,0x14,0xf0,0xfb};
        satcat5::aes::Gcm gcm(192,k_0,96,nonce_0);
        gcm.encrypt_decrypt(16,p_0,c);
        gcm.compute_tag(0,16,NULL,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 9") {
        const u8 exp_c[64] = {
            0x39,0x80,0xca,0x0b,0x3c,0x00,0xe8,0x41,0xeb,0x06,0xfa,0xc4,0x87,0x2a,0x27,0x57,
            0x85,0x9e,0x1c,0xea,0xa6,0xef,0xd9,0x84,0x62,0x85,0x93,0xb4,0x0c,0xa1,0xe1,0x9c,
            0x7d,0x77,0x3d,0x00,0xc1,0x44,0xc5,0x25,0xac,0x61,0x9d,0x18,0xc8,0x4a,0x3f,0x47,
            0x18,0xe2,0x44,0x8b,0x2f,0xe3,0x24,0xd9,0xcc,0xda,0x27,0x10,0xac,0xad,0xe2,0x56};
        const u8 exp_t[16] = {
            0x99,0x24,0xa7,0xc8,0x58,0x73,0x36,0xbf,0xb1,0x18,0x02,0x4d,0xb8,0x67,0x4a,0x14};
        satcat5::aes::Gcm gcm(192,k_2,96,nonce_1);
        gcm.encrypt_decrypt(64,p_1,c);
        gcm.compute_tag(0,64,NULL,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 10") {
        const u8 exp_c[60] = {
            0x39,0x80,0xca,0x0b,0x3c,0x00,0xe8,0x41,0xeb,0x06,0xfa,0xc4,0x87,0x2a,0x27,0x57,
            0x85,0x9e,0x1c,0xea,0xa6,0xef,0xd9,0x84,0x62,0x85,0x93,0xb4,0x0c,0xa1,0xe1,0x9c,
            0x7d,0x77,0x3d,0x00,0xc1,0x44,0xc5,0x25,0xac,0x61,0x9d,0x18,0xc8,0x4a,0x3f,0x47,
            0x18,0xe2,0x44,0x8b,0x2f,0xe3,0x24,0xd9,0xcc,0xda,0x27,0x10};
        const u8 exp_t[16] = {
            0x25,0x19,0x49,0x8e,0x80,0xf1,0x47,0x8f,0x37,0xba,0x55,0xbd,0x6d,0x27,0x61,0x8c};
        satcat5::aes::Gcm gcm(192,k_2,96,nonce_1);
        gcm.encrypt_decrypt(60,p_1,c);
        gcm.compute_tag(20,60,aad_1,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 11") {
        const u8 exp_c[60] = {
            0x0f,0x10,0xf5,0x99,0xae,0x14,0xa1,0x54,0xed,0x24,0xb3,0x6e,0x25,0x32,0x4d,0xb8,
            0xc5,0x66,0x63,0x2e,0xf2,0xbb,0xb3,0x4f,0x83,0x47,0x28,0x0f,0xc4,0x50,0x70,0x57,
            0xfd,0xdc,0x29,0xdf,0x9a,0x47,0x1f,0x75,0xc6,0x65,0x41,0xd4,0xd4,0xda,0xd1,0xc9,
            0xe9,0x3a,0x19,0xa5,0x8e,0x8b,0x47,0x3f,0xa0,0xf0,0x62,0xf7};
        const u8 exp_t[16] = {
            0x65,0xdc,0xc5,0x7f,0xcf,0x62,0x3a,0x24,0x09,0x4f,0xcc,0xa4,0x0d,0x35,0x33,0xf8};
        satcat5::aes::Gcm gcm(192,k_2,64,nonce_1);
        gcm.encrypt_decrypt(60,p_1,c);
        gcm.compute_tag(20,60,aad_1,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 12") {
        const u8 exp_c[60] = {
            0xd2,0x7e,0x88,0x68,0x1c,0xe3,0x24,0x3c,0x48,0x30,0x16,0x5a,0x8f,0xdc,0xf9,0xff,
            0x1d,0xe9,0xa1,0xd8,0xe6,0xb4,0x47,0xef,0x6e,0xf7,0xb7,0x98,0x28,0x66,0x6e,0x45,
            0x81,0xe7,0x90,0x12,0xaf,0x34,0xdd,0xd9,0xe2,0xf0,0x37,0x58,0x9b,0x29,0x2d,0xb3,
            0xe6,0x7c,0x03,0x67,0x45,0xfa,0x22,0xe7,0xe9,0xb7,0x37,0x3b};
        const u8 exp_t[16] = {
            0xdc,0xf5,0x66,0xff,0x29,0x1c,0x25,0xbb,0xb8,0x56,0x8f,0xc3,0xd3,0x76,0xa6,0xd9};
        satcat5::aes::Gcm gcm(192,k_2,480,nonce_2);
        gcm.encrypt_decrypt(60,p_1,c);
        gcm.compute_tag(20,60,aad_1,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 13") {
        const u8 exp_t[16] = {0x53,0x0f,0x8a,0xfb,0xc7,0x45,0x36,0xb9,0xa9,0x63,0xb4,0xf1,0xc4,0xcb,0x73,0x8b};
        satcat5::aes::Gcm gcm(256,k_0,96,nonce_0);
        gcm.encrypt_decrypt(0,p_0,c);
        gcm.compute_tag(0,0,NULL,c,t);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 14") {
        const u8 exp_c[16] = {0xCE,0xA7,0x40,0x3D,0x4D,0x60,0x6B,0x6E,0x07,0x4E,0xC5,0xD3,0xBA,0xF3,0x9D,0x18};
        const u8 exp_t[16] = {0xD0,0xD1,0xC8,0xA7,0x99,0x99,0x6B,0xF0,0x26,0x5B,0x98,0xB5,0xD4,0x8A,0xB9,0x19};
        satcat5::aes::Gcm gcm(256,k_0,96,nonce_0);
        gcm.encrypt_decrypt(16,p_0,c);
        gcm.compute_tag(0,16,NULL,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------

    SECTION("Test Case 15") {
        const u8 exp_c[64] = {
            0x52,0x2D,0xC1,0xF0,0x99,0x56,0x7D,0x07,0xF4,0x7F,0x37,0xA3,0x2A,0x84,0x42,0x7D,
            0x64,0x3A,0x8C,0xDC,0xBF,0xE5,0xC0,0xC9,0x75,0x98,0xA2,0xBD,0x25,0x55,0xD1,0xAA,
            0x8C,0xB0,0x8E,0x48,0x59,0x0D,0xBB,0x3D,0xA7,0xB0,0x8B,0x10,0x56,0x82,0x88,0x38,
            0xC5,0xF6,0x1E,0x63,0x93,0xBA,0x7A,0x0A,0xBC,0xC9,0xF6,0x62,0x89,0x80,0x15,0xAD};
        const u8 exp_t[16] = {
            0xB0,0x94,0xDA,0xC5,0xD9,0x34,0x71,0xBD,0xEC,0x1A,0x50,0x22,0x70,0xE3,0xCC,0x6C};
        satcat5::aes::Gcm gcm(256,k_2,96,nonce_1);
        gcm.encrypt_decrypt(64,p_1,c);
        gcm.compute_tag(0,64,NULL,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 16") {
        const u8 exp_c[60] = {
            0x52,0x2D,0xC1,0xF0,0x99,0x56,0x7D,0x07,0xF4,0x7F,0x37,0xA3,0x2A,0x84,0x42,0x7D,
            0x64,0x3A,0x8C,0xDC,0xBF,0xE5,0xC0,0xC9,0x75,0x98,0xA2,0xBD,0x25,0x55,0xD1,0xAA,
            0x8C,0xB0,0x8E,0x48,0x59,0x0D,0xBB,0x3D,0xA7,0xB0,0x8B,0x10,0x56,0x82,0x88,0x38,
            0xC5,0xF6,0x1E,0x63,0x93,0xBA,0x7A,0x0A,0xBC,0xC9,0xF6,0x62};
        const u8 exp_t[16] = {
            0x76,0xFC,0x6E,0xCE,0x0F,0x4E,0x17,0x68,0xCD,0xDF,0x88,0x53,0xBB,0x2D,0x55,0x1B};
        satcat5::aes::Gcm gcm(256,k_2,96,nonce_1);
        gcm.encrypt_decrypt(60,p_1,c);
        gcm.compute_tag(20,60,aad_1,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 17") {
        const u8 exp_c[60] = {
            0xc3,0x76,0x2d,0xf1,0xca,0x78,0x7d,0x32,0xae,0x47,0xc1,0x3b,0xf1,0x98,0x44,0xcb,
            0xaf,0x1a,0xe1,0x4d,0x0b,0x97,0x6a,0xfa,0xc5,0x2f,0xf7,0xd7,0x9b,0xba,0x9d,0xe0,
            0xfe,0xb5,0x82,0xd3,0x39,0x34,0xa4,0xf0,0x95,0x4c,0xc2,0x36,0x3b,0xc7,0x3f,0x78,
            0x62,0xac,0x43,0x0e,0x64,0xab,0xe4,0x99,0xf4,0x7c,0x9b,0x1f};
        const u8 exp_t[16] = {
            0x3a,0x33,0x7d,0xbf,0x46,0xa7,0x92,0xc4,0x5e,0x45,0x49,0x13,0xfe,0x2e,0xa8,0xf2};
        satcat5::aes::Gcm gcm(256,k_2,64,nonce_1);
        gcm.encrypt_decrypt(60,p_1,c);
        gcm.compute_tag(20,60,aad_1,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
    // --------------------------------------
    SECTION("Test Case 18") {
        const u8 exp_c[60] = {
            0x5a,0x8d,0xef,0x2f,0x0c,0x9e,0x53,0xf1,0xf7,0x5d,0x78,0x53,0x65,0x9e,0x2a,0x20,
            0xee,0xb2,0xb2,0x2a,0xaf,0xde,0x64,0x19,0xa0,0x58,0xab,0x4f,0x6f,0x74,0x6b,0xf4,
            0x0f,0xc0,0xc3,0xb7,0x80,0xf2,0x44,0x45,0x2d,0xa3,0xeb,0xf1,0xc5,0xd8,0x2c,0xde,
            0xa2,0x41,0x89,0x97,0x20,0x0e,0xf8,0x2e,0x44,0xae,0x7e,0x3f};
        const u8 exp_t[16] = {
            0xa4,0x4a,0x82,0x66,0xee,0x1c,0x8e,0xb0,0xc8,0xb5,0xd4,0xcf,0x5a,0xe9,0xf1,0x9a};
        satcat5::aes::Gcm gcm(256,k_2,480,nonce_2);
        gcm.encrypt_decrypt(60,p_1,c);
        gcm.compute_tag(20,60,aad_1,c,t);
        CHECK(memcmp(c, exp_c, sizeof(exp_c)) == 0);
        CHECK(memcmp(t, exp_t, sizeof(exp_t)) == 0);
    }
}
