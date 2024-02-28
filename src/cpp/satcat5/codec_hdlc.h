//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Inline HDLC encoder and decoder objects
//
// The High-Level Data Link Control (HDLC) protocol for the data-link
// layer.  This file implements the byte-stuffed "asynchronous framing"
// portion of that protocol defined in IETF RFC 1662 Section 4, which is
// typically used with byte-aligned physical layers such as RS-232.
//
// Higher-level functions including insertion of address and control
// headers, duplexing, I/S/U frames, and link-state management are NOT
// currently supported, but may be added in a future update.
//
// The encoder accepts a Writeable interface, inserts inter-frame "flag"
// tokens, appends a 16-bit or 32-bit checksum, and finally performs
// byte-stuffing for reserved token values.
//
// The decoder performs the inverse, accepting an HDLC stream one byte
// at a time through the Writeable interface, decoding the result,
// and forwarding valid frames to a different Writeable object.
//
// See also: Wikipedia article
//      https://en.wikipedia.org/wiki/High-Level_Data_Link_Control
// See also: ISO/IEC 3309:1984
//      https://law.resource.org/pub/in/bis/S04/is.11418.1.1986.pdf
// See also: RFC 1662
//      https://datatracker.ietf.org/doc/html/rfc1662#section-3.1
//

#pragma once

#include <satcat5/crc16_checksum.h>
#include <satcat5/eth_checksum.h>
#include <satcat5/io_checksum.h>

namespace satcat5 {
    namespace io {
        // Inline HDLC encoder (framing layer only)
        class HdlcEncoder : public satcat5::io::WriteableRedirect
        {
        public:
            // Permanently link this encoder to an output object.
            explicit HdlcEncoder(satcat5::io::Writeable* dst);

            // Set various encoding parameters:
            inline void set_mode_actrl(bool actrl)
                { m_bstuff.m_actrl = actrl; }
            void set_mode_crc32(bool mode32);

        private:
            // Helper class for byte-stuffing.
            class ByteStuff : public satcat5::io::Writeable {
            public:
                explicit ByteStuff(satcat5::io::Writeable* dst);
                unsigned get_write_space() const override;
                void write_abort() override;
                bool write_finalize() override;
                void write_next(u8 data) override;
                satcat5::io::Writeable* const m_dst;    // Output object
                bool m_actrl;                           // Escape < 0x20?
            } m_bstuff;

            // Append checksum using the selected algorithm.
            satcat5::eth::ChecksumTx m_crc32;
            satcat5::crc16::KermitTx m_crc16;
        };

        // Inline HDLC decoder (framing layer only)
        class HdlcDecoder : public satcat5::io::Writeable
        {
        public:
            // Permanently link this encoder to an output object.
            explicit HdlcDecoder(satcat5::io::Writeable* dst);

            // Implement required API from Writeable:
            unsigned get_write_space() const override;

            // Set various decoding parameters:
            inline void set_mode_actrl(bool actrl)
                { m_actrl = actrl; }
            void set_mode_crc32(bool mode32);   // Append CRC32 or CRC16?

        private:
            // Implement required API from Writeable:
            void write_next(u8 data) override;
            void write_overflow() override;

            // Verify checksum using the selected algorithm.
            satcat5::eth::ChecksumRx m_crc32;
            satcat5::crc16::KermitRx m_crc16;

            // Internal state:
            enum class State {HDLC_RDY, HDLC_ESC, HDLC_EOF, HDLC_ERR};
            satcat5::io::HdlcDecoder::State m_state;    // Decoder state
            bool m_actrl;                               // Escape < 0x20?
            satcat5::io::Writeable* m_crc;              // CRC16 or CRC32?
        };
    }
}
