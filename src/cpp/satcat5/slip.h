//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// Inline SLIP encoder and decoder objects
//
// The inline SLIP encoder implements the Writeable interface, encodes each
// incoming byte, and writes the result to a different Writeable object with
// escape characters and inter-frame tokens.
//
// The inline SLIP decoder does the inverse, accepting an SLIP stream one byte
// at a time through the Writeable interface, and forwarding the decoded result
// to a different Writeable object.  (Often a PacketBuffer.)
//
// See also: IETF RFC-1055: "Serial Line Internet Protocol"
//      https://tools.ietf.org/html/rfc1055

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
        // Inline SLIP encoder
        class SlipEncoder : public satcat5::io::Writeable
        {
        public:
            // Permanently link this encoder to an output object.
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

        // Inline SLIP decoder
        class SlipDecoder : public satcat5::io::Writeable
        {
        public:
            // Permanently link this encoder to an output object.
            explicit SlipDecoder(satcat5::io::Writeable* dst);

            // Implement required API from Writeable:
            unsigned get_write_space() const override;

        private:
            // Implement required API from Writeable:
            void write_next(u8 data) override;

            // Internal state:
            enum class State {SLIP_RDY, SLIP_ESC, SLIP_EOF, SLIP_ERR};
            satcat5::io::Writeable* const m_dst;        // Output object
            satcat5::io::SlipDecoder::State m_state;    // Decoder state
        };

        // Buffered SLIP encoder / decoder pair.
        // (Suitable for connecting to UART or similar.)
        class SlipCodec
            : public satcat5::io::SlipEncoder
            , public satcat5::io::ReadableRedirect
        {
        public:
            // Constructor links to specified source and destination.
            // (Which are often the same BufferedIO object.)
            SlipCodec(
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);

        protected:
            // Rx path: Pull input -> SLIP decode -> buffer
            satcat5::io::PacketBuffer m_rx;         // Decoder writes to buffer
            satcat5::io::SlipDecoder m_decode;      // Decoder object
            satcat5::io::BufferedCopy m_copy;       // Push/pull adapter
            u8 m_rxbuff[SATCAT5_SLIP_BUFFSIZE];     // Working buffer for m_rx
        };
    }
}
