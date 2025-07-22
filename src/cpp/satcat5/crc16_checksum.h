//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Inline CRC16 Checksum insertion and verification.
//!
//!\details
//! This file defines two commonly-used formats for "CCITT" CRC16 checksums.
//! Both are commonly used variants of the "CRC16-CCITT" standard defined
//! in ITU-T Recommendation V.41.  "KERMIT" is the LSB-first variant and
//! "XMODEM" is the MSB-first variant.
//!
//! For more information, see discussion from Greg Cook:
//!  https://reveng.sourceforge.io/crc-catalogue/16.htm#crc.cat.crc-16-ibm-3740
//!  https://reveng.sourceforge.io/crc-catalogue/16.htm#crc.cat.crc-16-kermit
//!  https://reveng.sourceforge.io/crc-catalogue/16.htm#crc.cat.crc-16-xmodem
//!
//! The blocks below transmit or receive sequences where the the CRC16 appears
//! at the end of the encoded frame. The `KermitTx` and `XmodemTx` classes
//! accept the frame contents and append the designated CRC16 variant. The
//! `KermitRx` and `XmodemRx` classes verify the checksum of incoming frames,
//! calling write_finalize() or write_abort() appropriately.
//!
//! Note that the CRC16 used in the CCSDS "AOS Space Data Link Protocol"
//! (Blue Book 732.0-B-4) is equivalent to "IBM-3740" (link above), which is
//! the "XMODEM" variant with an initial value of 0xFFFF instead of zero.

#pragma once

#include <satcat5/io_checksum.h>

namespace satcat5 {
    namespace crc16 {
        //! Directly calculate CRC16 on a block of data.
        //! This is the "KERMIT" variant, \see crc16_checksum.h.
        u16 kermit(unsigned nbytes, const void* data);
        //! Directly calculate CRC16 on a block of data.
        //! This is the "XMODEM" variant, \see crc16_checksum.h.
        u16 xmodem(unsigned nbytes, const void* data);

        //! Append FCS to each outgoing frame ("KERMIT" variant).
        //! Initial value is usually zero, but 0xFFFF is also common.
        //! \see crc16_checksum.h, crc16::KermitTx.
        class KermitTx : public satcat5::io::ChecksumTx<u16,2> {
        public:
            explicit KermitTx(satcat5::io::Writeable* dst, u16 init = 0, u16 xorout = 0);
            bool write_finalize() override;
        private:
            void write_next(u8 data) override;
            const u16 m_xorout;
        };

        //! Check and remove FCS from each incoming frame ("KERMIT" variant).
        //! \see crc16_checksum.h, crc16::KermitTx.
        class KermitRx : public satcat5::io::ChecksumRx<u16,2> {
        public:
            explicit KermitRx(satcat5::io::Writeable* dst, u16 init = 0, u16 xorout = 0);
            bool write_finalize() override;
        private:
            void write_next(u8 data) override;
            const u16 m_xorout;
        };

        //! Append FCS to each outgoing frame ("XMODEM" variant).
        //! \see crc16_checksum.h, crc16::XmodemRx.
        class XmodemTx : public satcat5::io::ChecksumTx<u16,2> {
        public:
            explicit XmodemTx(satcat5::io::Writeable* dst, u16 init = 0, u16 xorout = 0);
            bool write_finalize() override;
        private:
            void write_next(u8 data) override;
            const u16 m_xorout;
        };

        //! Check and remove FCS from each incoming frame ("XMODEM" variant).
        //! \see crc16_checksum.h, crc16::XmodemTx.
        class XmodemRx : public satcat5::io::ChecksumRx<u16,2> {
        public:
            explicit XmodemRx(satcat5::io::Writeable* dst, u16 init = 0, u16 xorout = 0);
            bool write_finalize() override;
        private:
            void write_next(u8 data) override;
            const u16 m_xorout;
       };
    }
}
