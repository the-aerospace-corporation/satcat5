//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Inline SLIP encoder and decoder objects.
//!
//!\details
//! The inline `SlipEncoder` implements the Writeable interface, encodes each
//! incoming byte, and writes the result to a different Writeable object with
//! escape characters and inter-frame tokens.
//!
//! The inline `SlipDecoder` does the inverse, accepting an SLIP stream one byte
//! at a time through the Writeable interface, and forwarding the decoded result
//! to a different Writeable object.  (Often a PacketBuffer.)
//!
//! In both cases, the input uses the `io::Writeable` API.  To attach either
//! input to an `io::Readable` interface, use `io::BufferedCopy`.
//!
//! See also: IETF RFC-1055: "Serial Line Internet Protocol"
//!      https://tools.ietf.org/html/rfc1055

#pragma once

#include <satcat5/io_buffer.h>
#include <satcat5/pkt_buffer.h>

// Default size parameters
// (Must be large enough for one full-size Ethernet frame + metadata,
//  larger sizes are fine if you have the memory for it.)
#ifndef SATCAT5_SLIP_BUFFSIZE
#define SATCAT5_SLIP_BUFFSIZE   1600    // One full-size Ethernet frame
#endif

#ifndef SATCAT5_SLIP_PACKETS
#define SATCAT5_SLIP_PACKETS    32      // ...or many smaller frames
#endif

namespace satcat5 {
    namespace io {
        //! Inline SLIP encoder. \see codec_slip.h.
        class SlipEncoder : public satcat5::io::Writeable {
        public:
            //! Permanently link this encoder to an output object.
            explicit SlipEncoder(satcat5::io::Writeable* dst);

            // Implement required API from Writeable:
            unsigned get_write_space() const override;
            bool write_finalize() override;
            void write_overflow() override;

        private:
            // Implement required API from Writeable:
            void write_next(u8 data) override;

            // Internal state:
            satcat5::io::Writeable* const m_dst;    // Output object
            bool m_overflow;
        };

        //! Inline SLIP decoder. \see codec_slip.h.
        class SlipDecoder : public satcat5::io::Writeable {
        public:
            //! Permanently link this encoder to an output object.
            explicit SlipDecoder(satcat5::io::Writeable* dst);

            // Implement required API from Writeable:
            unsigned get_write_space() const override;

        private:
            // Implement required API from Writeable:
            void write_next(u8 data) override;
            void write_overflow() override;

            // Internal state:
            enum class State {SLIP_RDY, SLIP_ESC, SLIP_EOF, SLIP_ERR};
            satcat5::io::Writeable* const m_dst;        // Output object
            satcat5::io::SlipDecoder::State m_state;    // Decoder state
        };

        //! Buffered SLIP encoder / decoder pair.
        //! Suitable for connecting to UART or similar.
        //!
        //! Tx path: Write (*this) -> SLIP encode (parent) -> Write (*dst)
        //!
        //! Rx path: Read (*src) -> SLIP decode -> Buffer -> Read (*this)
        class SlipCodec
            : public satcat5::io::SlipEncoder
            , public satcat5::io::ReadableRedirect
        {
        public:
            //! Constructor links to specified source and destination.
            //! In many cases, `dst` and `src` are the same BufferedIO object.
            SlipCodec(
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);

        protected:
            satcat5::io::PacketBuffer m_buff;       //!< Decoder writes to buffer
            satcat5::io::SlipDecoder m_decode;      //!< Decoder object
            satcat5::io::BufferedCopy m_copy;       //!< Push/pull adapter
            u8 m_rawbuff[SATCAT5_SLIP_BUFFSIZE];    //!< Working buffer for m_rx
        };

        //! Buffered SLIP encoder / decoder pair with opposite polarity.
        //! Suitable for use in unit testing and verification.
        //! This configuration is not typically useful in deployed hardware.
        //!
        //! Rx path: Write (*this) -> SLIP decode (parent) -> Write (*dst)
        //!
        //! Tx path: Read (*src) -> SLIP encode -> Buffer -> Read (*this)
        class SlipCodecInverse
            : public satcat5::io::SlipDecoder
            , public satcat5::io::ReadableRedirect
        {
        public:
            //! Constructor links to specified source and destination.
            //! In many cases, `dst` and `src` are the same BufferedIO object.
            SlipCodecInverse(
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);

        protected:
            satcat5::io::PacketBuffer m_buff;       //!< Encoder writes to buffer
            satcat5::io::SlipEncoder m_encode;      //!< Encoder object
            satcat5::io::BufferedCopy m_copy;       //!< Push/pull adapter
            u8 m_rawbuff[SATCAT5_SLIP_BUFFSIZE];    //!< Working buffer for m_rx
        };
    }
}
