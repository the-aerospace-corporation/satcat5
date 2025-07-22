//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Inline Ethernet Checksum insertion and verification.
//!
//!\details
//! Every Ethernet frame contains a "Frame Check Sequence" (FCS).  In many
//! cases, the FCS is automatically added or removed by drivers, by hardware
//! logic, etc., so that it does not need to be handled in software.  (This
//! includes SatCat5 HDL blocks such as port_mailbox and port_mailmap.)
//!
//! The blocks below are provided for cases that do not provide this service.
//! Each is implemented as an inline layer using Readable/Writeable streams.
//!  * `eth::ChecksumTx` appends an FCS to each outgoing frame.
//!  * `eth::ChecksumRx` checks the FCS of each incoming frame and calls
//!    either write_finalize() or write_abort() appropriately.
//!  * `eth::SlipCodec` combines both of the above PLUS a SLIP encoder and
//!    decoder.  This makes it easy to send and receive SLIP-encoded Ethernet
//!    frames over an SPI or UART port, for example.

#pragma once

#include <satcat5/codec_slip.h>
#include <satcat5/io_buffer.h>
#include <satcat5/io_checksum.h>

namespace satcat5 {
    namespace eth {
        //! Directly calculate CRC32 on a block of data.
        u32 crc32(unsigned nbytes, const void* data);

        //! Read data from source and calculate CRC32.
        u32 crc32(satcat5::io::Readable* src);

        //! Append FCS to each outgoing frame.
        class ChecksumTx : public satcat5::io::ChecksumTx<u32,4> {
        public:
            //! Permanently link this encoder to an output object.
            explicit ChecksumTx(satcat5::io::Writeable* dst);

            // Implement required API from Writeable:
            bool write_finalize() override;

        private:
            // Implement required API from Writeable:
            void write_next(u8 data) override;
        };

        //! Check and remove FCS from each incoming frame.
        class ChecksumRx : public satcat5::io::ChecksumRx<u32,4> {
        public:
            //! Permanently link this encoder to an output object.
            explicit ChecksumRx(satcat5::io::Writeable* dst);

            // Implement required API from Writeable:
            bool write_finalize() override;

        private:
            // Implement required API from Writeable:
            void write_next(u8 data) override;
        };

        //! Buffered SLIP encoder / decoder pair with Ethernet FCS.
        //! Suitable for connecting to UART or similar.
        //!
        //! Tx path: Write (*this) -> Append FCS (parent) -> SLIP encode -> Write (*dst)
        //!
        //! Rx path: Read (*src) -> SLIP decode -> Verify FCS -> Buffer -> Read (*this)
        class SlipCodec
            : public satcat5::io::ReadableRedirect
            , public satcat5::eth::ChecksumTx
        {
        public:
            //! Constructor links to specified source and destination.
            //! (Which are often the same BufferedIO object.)
            SlipCodec(
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);

        protected:
            satcat5::io::SlipEncoder m_tx_slip;     //!< SLIP encoder object
            satcat5::io::BufferedCopy m_rx_copy;    //!< Push/pull adapter
            satcat5::io::SlipDecoder m_rx_slip;     //!< SLIP decoder object
            satcat5::eth::ChecksumRx m_rx_fcs;      //!< Verify received checksums
            satcat5::io::PacketBuffer m_rx_buff;    //!< Decoder writes to buffer
            u8 m_rawbuff[SATCAT5_SLIP_BUFFSIZE];    //!< Working buffer for m_rx_buff
        };

        //! Inverted SLIP encoder / decoder pair with Ethernet FCS.
        //! Suitable for use in unit testing and simulation.
        //! This configuration is not typically useful in deployed hardware.
        //!
        //! Rx path: Write (*this) -> SLIP decode (parent) -> Verify FCS -> Write (*dst)
        //!
        //! Tx path: Read (*src) -> Append FCS -> SLIP encode -> Buffer -> Read (*this)
        class SlipCodecInverse
            : public satcat5::io::ReadableRedirect
            , public satcat5::io::SlipDecoder
        {
        public:
            //! Constructor links to specified source and destination.
            //! (Which are often the same BufferedIO object.)
            SlipCodecInverse(
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);

        protected:
            satcat5::eth::ChecksumRx m_rx_fcs;      //!< Verify received checksums
            satcat5::io::BufferedCopy m_tx_copy;    //!< Push/pull adapter
            satcat5::eth::ChecksumTx m_tx_fcs;      //!< Append outgoing checksums
            satcat5::io::SlipEncoder m_tx_slip;     //!< SLIP encoder object
            satcat5::io::PacketBuffer m_tx_buff;    //!< Decoder writes to buffer
            u8 m_rawbuff[SATCAT5_SLIP_BUFFSIZE];    //!< Working buffer for m_tx_buff
        };
    }
}
