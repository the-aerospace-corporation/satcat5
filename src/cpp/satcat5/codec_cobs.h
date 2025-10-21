//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Inline COBS encoder and decoder objects.
//!
//!\details
//! Consistent Overhead Byte Stuffing (COBS) is a packet-delimiting protocol.
//! Its function is similar to SLIP, with equivalent *average* overhead but
//! much better worst-case: just ceil(n/254) additional bytes vs. SLIP's
//! potential to double packet length in extreme cases. \see codec_slip.h
//!
//! The inline `CobsEncoder` implements the Writeable interface, encodes each
//! incoming byte, and writes the result to a different Writeable object with
//! encoded data and inter-frame tokens.
//!
//! The inline `CobsDecoder` does the inverse, accepting a COBS stream one byte
//! at a time through the Writeable interface, and forwarding the decoded result
//! to a different Writeable object.  (Often a PacketBuffer.)
//!
//! In both cases, the input uses the `io::Writeable` API.  To attach either
//! input to an `io::Readable` interface, use `io::BufferedCopy`.
//!
//! See also:
//! https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing
//! http://www.stuartcheshire.org/papers/COBSforToN.pdf
//!

#pragma once

#include <satcat5/io_buffer.h>
#include <satcat5/pkt_buffer.h>

// Default size parameters
// (Must be large enough for one full-size Ethernet frame + metadata,
//  larger sizes are fine if you have the memory for it.)
#ifndef SATCAT5_COBS_BUFFSIZE
#define SATCAT5_COBS_BUFFSIZE   1600    // One full-size Ethernet frame
#endif

#ifndef SATCAT5_COBS_PACKETS
#define SATCAT5_COBS_PACKETS    32      // ...or many smaller frames
#endif

namespace satcat5 {
    namespace io {
        //! Inline COBS encoder. \see codec_cobs.h.
        class CobsEncoder : public satcat5::io::Writeable {
        public:
            //! Permanently link this encoder to an output object.
            explicit CobsEncoder(satcat5::io::Writeable* dst);

            // Implement required API from Writeable:
            unsigned get_write_space() const override;
            bool write_finalize() override;
            void write_overflow() override;

        private:
            // Implement required API from Writeable:
            void write_next(u8 data) override;

            // Flush the lookahead buffer.
            void flush_segment();

            // Internal state:
            satcat5::io::Writeable* const m_dst;    // Output object
            u8 m_ctr;                               // Run-length counter
            u8 m_ovr;                               // Overflow flag
            u8 m_buf[254];                          // Lookahead buffer
        };

        //! Inline COBS decoder. \see codec_cobs.h.
        class CobsDecoder : public satcat5::io::Writeable {
        public:
            //! Permanently link this encoder to an output object.
            explicit CobsDecoder(satcat5::io::Writeable* dst);

            // Implement required API from Writeable:
            unsigned get_write_space() const override;

        private:
            // Implement required API from Writeable:
            void write_next(u8 data) override;
            void write_overflow() override;

            // Internal state:
            satcat5::io::Writeable* const m_dst;        // Output object
            u8 m_blk;                                   // Block type
            u8 m_ctr;                                   // Bytes remaining
            u8 m_ovr;                                   // Overflow flag
        };

        //! Buffered COBS encoder / decoder pair.
        //! Suitable for connecting to UART or similar.
        //!
        //! This class provides COBS encoding only, with no validation.
        //! For related classes that include CRC32, \see eth_checksum.h.
        //!
        //! Tx path: Write (*this) -> COBS encode (parent) -> Write (*dst)
        //!
        //! Rx path: Read (*src) -> COBS decode -> Buffer -> Read (*this)
        class CobsCodec
            : public satcat5::io::CobsEncoder
            , public satcat5::io::ReadableRedirect
        {
        public:
            //! Constructor links to specified source and destination.
            //! In many cases, `dst` and `src` are the same BufferedIO object.
            CobsCodec(
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);

        protected:
            satcat5::io::PacketBuffer m_buff;       //!< Decoder writes to buffer
            satcat5::io::CobsDecoder m_decode;      //!< Decoder object
            satcat5::io::BufferedCopy m_copy;       //!< Push/pull adapter
            u8 m_rawbuff[SATCAT5_COBS_BUFFSIZE];    //!< Working buffer for m_rx
        };

        //! Buffered COBS encoder / decoder pair with opposite polarity.
        //! Suitable for use in unit testing and verification.
        //! This configuration is not typically useful in deployed hardware.
        //!
        //! Rx path: Write (*this) -> COBS decode (parent) -> Write (*dst)
        //!
        //! Tx path: Read (*src) -> COBS encode -> Buffer -> Read (*this)
        class CobsCodecInverse
            : public satcat5::io::CobsDecoder
            , public satcat5::io::ReadableRedirect
        {
        public:
            //! Constructor links to specified source and destination.
            //! In many cases, `dst` and `src` are the same BufferedIO object.
            CobsCodecInverse(
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);

        protected:
            satcat5::io::PacketBuffer m_buff;       //!< Encoder writes to buffer
            satcat5::io::CobsEncoder m_encode;      //!< Encoder object
            satcat5::io::BufferedCopy m_copy;       //!< Push/pull adapter
            u8 m_rawbuff[SATCAT5_COBS_BUFFSIZE];    //!< Working buffer for m_rx
        };
    }
}
