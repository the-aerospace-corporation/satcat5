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
// Inline Ethernet Checksum insertion and verification
//
// Every Ethernet frame contains a "Frame Check Sequence" (FCS).  In many
// cases, the FCS is automatically added or removed by drivers, by hardware
// logic, etc., so that it does not need to be handled in software.  (This
// includes SatCat5 HDL blocks such as port_mailbox and port_mailmap.)
//
// The blocks below are provided for cases that do not provide this service.
// Each is implemented as an inline layer using Readable/Writeable streams.
//  * "eth::ChecksumTx" appends an FCS to each outgoing frame.
//  * "eth::ChecksumRx" checks the FCS of each incoming frame and calls
//    either write_finalize() or write_abort() appropriately.
//  * "eth::SlipCodec" combines both of the above PLUS a SLIP encoder and
//    decoder.  This makes it easy to send and receive SLIP-encoded Ethernet
//    frames over an SPI or UART port, for example.
//

#pragma once

#include <satcat5/io_buffer.h>
#include <satcat5/slip.h>

namespace satcat5 {
    namespace eth {
        // Directly calculate CRC32 on a block of data.
        u32 crc32(unsigned nbytes, const void* data);

        // Read data from source and calculate CRC32.
        u32 crc32(satcat5::io::Readable* src);

        // Append FCS to each outgoing frame.
        class ChecksumTx : public satcat5::io::Writeable
        {
        public:
            // Permanently link this encoder to an output object.
            explicit ChecksumTx(satcat5::io::Writeable* dst);

            // Implement required API from Writeable:
            unsigned get_write_space() const override;
            bool write_finalize() override;
            void write_abort() override;

        private:
            // Implement required API from Writeable:
            void write_next(u8 data) override;

            // Internal state:
            satcat5::io::Writeable* const m_dst;    // Output object
            u32 m_crc;                              // Checksum state
        };

        // Check and remove FCS from each incoming frame.
        class ChecksumRx : public satcat5::io::Writeable
        {
        public:
            // Permanently link this encoder to an output object.
            explicit ChecksumRx(satcat5::io::Writeable* dst);

            // Implement required API from Writeable:
            unsigned get_write_space() const override;
            bool write_finalize() override;
            void write_abort() override;

        private:
            // Implement required API from Writeable:
            void write_next(u8 data) override;

            // Internal state:
            satcat5::io::Writeable* const m_dst;    // Output object
            u32 m_crc;                              // Checksum state
            u32 m_sreg;                             // Input delay buffer
            unsigned m_bidx;                        // Bytes received
        };

        // Buffered SLIP encoder / decoder pair with Ethernet FCS.
        // (Suitable for connecting to UART or similar.)
        class SlipCodec
            : public satcat5::io::ReadableRedirect
            , public satcat5::eth::ChecksumTx
        {
        public:
            // Constructor links to specified source and destination.
            // (Which are often the same BufferedIO object.)
            SlipCodec(
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);

        protected:
            // Tx path: Raw input -> append FCS (parent) -> SLIP encode -> output
            satcat5::io::SlipEncoder m_tx_slip;     // SLIP encoder object
            // Rx path: Pull input -> SLIP decode -> check FCS -> buffer
            satcat5::io::BufferedCopy m_rx_copy;    // Push/pull adapter
            satcat5::io::SlipDecoder m_rx_slip;     // SLIP decoder object
            satcat5::eth::ChecksumRx m_rx_fcs;      // Verify Rx-checksums
            satcat5::io::PacketBuffer m_rx;         // Decoder writes to buffer
            u8 m_rxbuff[SATCAT5_SLIP_BUFFSIZE];     // Working buffer for m_rx
        };
    }
}
