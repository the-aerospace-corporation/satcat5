//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Implement IEEE 802.1ae MACsec

#pragma once
#include <satcat5/aes_gcm.h>
#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>

namespace satcat5 {
    namespace eth {
        //! Implement IEEE 802.1ae MACsec.
        //! https://standards.ieee.org/standard/802_1AE-2018.html
        //!
        //! The eth::MacSec object is initialized with a session key, a
        //! nonce/IV (called "Salt" in the IEEE specification), and
        //! configuration (tci/an). The link-IV is effectively constant
        //! for a given key association.
        //!
        //! In MACsec XPN, each frame is encrypted/authenticated with its
        //! own IV, which is determined by the session's IV XOR'd with a
        //! short secure channel ID (SSCI = 4-bytes) and with the frame's
        //! unique packet number (PN = 8-bytes).
        //!
        //! The 12-byte frame IV is then given by the link-IV (salt), SSCI, and PN:
        //!```
        //!     Salt:   IV[0]   IV[1]   IV[2]   IV[3]   IV[4]  IV[5]  IV[6]  IV[7]  IV[8]  IV[9]  IV[10]  IV[11]
        //!      xor  SSCI[0] SSCI[1] SSCI[2] SSCI[3]  PN_MSB  ...    ...   ...    ...    ...     ...     PN_LSB
        //!```
        //!
        //! The counter starts from 0 with each frame, and each frame has at
        //! most 1500 bytes (i.e., 93 blocks of 16-bytes each).  So the
        //! AES-encrypted counter sequence counter used to encrypt the bytes
        //! of a given frame is given by:
        //!```
        //!      first 16 bytes  {FrameIV} + 0  0  0  1
        //!      next 16 bytes   {FrameIV} + 0  0  0  2
        //!      next 16 bytes   {FrameIV} + 0  0  0  3
        //!      ...up to the end of the frame...
        //!      last  16 bytes  {FrameIV} + 0  0  5  D
        //!```
        //!
        //! The next frame will have a different packet number, which yields a
        //! different IV. This ensures that, as long as PN < 2^64, a counter is
        //! never reused for a particular session. The SCI corresponds to a
        //! given MAC address and port identifer. Since we are initially only
        //! using a single channel, TX, and RX, we WLOG we will generally set
        //! SCI equal to 0. We store SCI as a variable but do not require it
        //! be used.
        //!
        //! For each frame (i.e., each call of encrypt/decrypt), the IV of the
        //! GCM object is updated using the IV xor PN.
        class MacSec {
        public:
            //! Regular mode (GCM-AES-128 or GCM-AES-256).
            MacSec(unsigned key_len_bits, const u8* key,
                u8 tci_an = 0x0C, u64 sci = 0);

            //! Extended mode (GCM-AES-XPN-128 or GCM-AES-XPN-256).
            //! In addition to above, requires a 96-bit "salt" and an SSCI.
            MacSec(unsigned key_len_bits, const u8* key, const u8* salt,
                u8 tci_an = 0x0C, u64 sci = 0, u32 ssci = 0);

            //! Encrypt a single frame.  (Input should not include FCS.)
            //! Returns true if encryption succeeded, false on error.
            bool encrypt_frame(
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst,
                u64 packet_number);

            //! Decrypt a single frame.  (Input should not include FCS.)
            //! Returns true if decryption and authentication succeeded.
            bool decrypt_frame(
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst,
                u64& packet_number);

        protected:
            void set_gcm_frame_iv(u64 packet_number);
            void calculate_icv(unsigned len_tot, const u8* frame, u8* icv);

            satcat5::aes::Gcm m_gcm;
            u64 m_sci;
            u32 m_ssci;
            bool m_xpn;
            bool m_error;
            u8 m_tci;
            u8 m_salt[12];
        };
    }
}
