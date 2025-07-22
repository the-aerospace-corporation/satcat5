//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Buffered I/O wrappers for PacketBuffer
//! \details
//! This file defines the "BufferedIO" class which adds buffered "writeable"
//! and "readable" interfaces to a child class.  It also defines several
//! tools for automatically copying between various sources and sinks.

#pragma once

#include <satcat5/io_core.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/timeref.h>

namespace satcat5 {
    namespace io {
        //! Extensible transmit and receive buffer
        //!
        //! The BufferedIO class provides a flexible software buffer for use
        //! with hardware I/O functions, such as Ethernet, I2C, and UART ports.
        //! It grants the public `Writable` and `Readable` interfaces and makes
        //! the buffered data available to the inner class.
        //
        //! To use, set up a parent class that:
        //!  * Inherits from BufferedIO.
        //!  * Provides the raw working buffers for each PacketBuffer instance.
        //!  * Passes the parameters for these to the BufferedIO constructor.
        //!    (These buffers can be used in packet mode or contiguous mode.)
        //!  * Implements the `data_rcvd()` method to handle new outgoing data.
        //!    (i.e., By calling the read_xx methods on `m_tx`.)
        //!  * Writes any incoming received data to the `m_rx` buffer.
        //!
        //! The child SHOULD access each PacketBuffer `m_tx` and `m_rx` directly
        //! and MUST implement `EventListener::data_rcvd()`.
        class BufferedIO
            : public    satcat5::io::ReadableRedirect
            , public    satcat5::io::WriteableRedirect
            , protected satcat5::io::EventListener
        {
        protected:
            //! Child provides Tx and Rx working buffers.
            BufferedIO(
                u8* txbuff, unsigned txbytes, unsigned txpkt,
                u8* rxbuff, unsigned rxbytes, unsigned rxpkt);
            ~BufferedIO() {}

            // Child MUST implement the following inherited methods:
            //  void data_rcvd(satcat5::io::Readable* src) override;

            //! Transmit data (user writes, child reads)
            satcat5::io::PacketBuffer m_tx;

            //! Receive data  (user reads, child writes)
            satcat5::io::PacketBuffer m_rx;
        };

        //! BufferedCopy copies from any Readable source to any Writeable sink.
        //! To use: Pass the source and sink pointers to the constructor. Work
        //!         is performed during satcat5::poll::service().
        class BufferedCopy final
            : public satcat5::io::EventListener
        {
        public:
            //! Create an object that copies data from `src` to `dst`.
            //! In packet mode (default), `write_finalize` is only called
            //! when the input reaches the end of each packet.  In stream
            //! mode, `write_finalize` is called every time data is copied.
            //! \param src Data source to be read.
            //! \param dst Destination to be written.
            //! \param mode Set operating mode. \see CopyMode.
            BufferedCopy(
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst,
                satcat5::io::CopyMode mode = CopyMode::PACKET);
            ~BufferedCopy() SATCAT5_OPTIONAL_DTOR;

            //! Other accessors.
            //!@{
            inline satcat5::io::Writeable* dst()
                { return m_dst; }
            inline satcat5::io::Readable* src()
                { return m_src; }
            //!@}

        protected:
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;

            satcat5::io::Readable* m_src;
            satcat5::io::Writeable* const m_dst;
            satcat5::io::CopyMode m_mode;
        };

        //! Copy data from a Readable source to a network address.
        //!
        //! Given a buffered source of data and a maximum chunk size, read
        //! data in chunks and stream each chunk to a net::Address.  The source
        //! is usually a byte-stream that does not include packet boundaries.
        //!
        //! Usage is similar to BufferedCopy, but with improved controls for
        //! packetizing the raw stream. Two thresholds control the length of
        //! outgoing packets:
        //! * Threshold "max_chunk" is the absolute maximum length.
        //!   i.e., Outgoing packets MUST NOT exceed max_chunk bytes.
        //! * Threshold "min_txnow" sets the preferred minimum length.
        //!   i.e., Outgoing packets SHOULD be at least min_txnow bytes,
        //!   but MAY be smaller if incoming data has slowed or stopped.
        //!
        //! To prevent trailing data from becoming stuck, a timeout allows
        //! transmission of smaller chunks as follows.  With N as the number
        //! of bytes available from the Readable source:
        //! * If N >= max_chunk: Transmit max_chunk bytes immediately.
        //! * Optionally, if N >= min_txnow: Transmit N bytes immediately.
        //!   (This condition is ignored if min_txnow >= max_chunk.)
        //! * Otherwise: Wait for transmit timeout, then transmit N bytes.
        //!   (This condition is ignored if the trantmit timeout is zero.)
        class BufferedStream final
            : public satcat5::io::EventListener
        {
        public:
            //! Set source, destination, APID, and chunk-size.
            //! Default sets max_chunk to 512 bytes and ignores min_txnow.
            BufferedStream(
                satcat5::io::Readable* src,
                satcat5::net::Address* dst,
                unsigned max_chunk = 512,
                unsigned min_txnow = UINT_MAX);
            ~BufferedStream() SATCAT5_OPTIONAL_DTOR;

            //! Set packetization timeout, in milliseconds.
            //! If the timeout is zero, copy only full-size chunks.
            inline void set_timeout(unsigned msec)
                { m_timeout_msec = msec; }

        protected:
            // Required event handlers.
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;

            // Member variables.
            satcat5::io::Readable* m_src;
            satcat5::net::Address* const m_dst;
            const unsigned m_max_chunk;
            const unsigned m_min_txnow;
            unsigned m_timeout_msec;
            satcat5::util::TimeVal m_tref;
        };

        //! BufferedWriter adds an inline buffer to any Writeable interface.
        //! To use: Pass the next-hop Writeable pointer to the constructor,
        //!         and write all data to the BufferedWriter object.
        class BufferedWriter
            : public satcat5::io::WriteableRedirect
        {
        public:
            BufferedWriter(
                satcat5::io::Writeable* dst,
                u8* txbuff, unsigned txbytes, unsigned txpkt);

        protected:
            satcat5::io::PacketBuffer m_buff;
            satcat5::io::BufferedCopy m_copy;
        };
    }
}
