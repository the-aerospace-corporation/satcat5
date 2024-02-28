//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2022 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Buffered I/O wrappers for PacketBuffer
//
// This file defines the "BufferedIO" class which adds buffered "writeable"
// and "readable" interfaces to a child class.  It also defines several
// tools for automatically copying between various sources and sinks.

#pragma once

#include <satcat5/io_core.h>
#include <satcat5/pkt_buffer.h>

namespace satcat5 {
    namespace io {
        // The BufferedIO class provides a flexible software buffer for use
        // with hardware I/O functions, such as Ethernet, I2C, and UART ports.
        // It grants the public "Writable" and "Readable" interfaces and makes
        // the buffered data available to the inner class.
        //
        // To use, set up a parent class that:
        //  * Inherits from BufferedIO.
        //  * Provides the raw working buffers for each PacketBuffer instance.
        //  * Passes the parameters for these to the BufferedIO constructor.
        //    (These buffers can be used in packet mode or contiguous mode.)
        //  * Implements the "data_rcvd()" method to handle new outgoing data.
        //    (i.e., By calling the read_xx methods on "m_tx".)
        //  * Writes any incoming received data to the "m_rx" buffer.
        class BufferedIO
            : public    satcat5::io::ReadableRedirect
            , public    satcat5::io::WriteableRedirect
            , protected satcat5::io::EventListener
        {
        protected:
            // Child provides Tx and Rx working buffers.
            BufferedIO(
                u8* txbuff, unsigned txbytes, unsigned txpkt,
                u8* rxbuff, unsigned rxbytes, unsigned rxpkt);
            ~BufferedIO() {}

            // Child MUST implement the following inherited methods:
            //  void data_rcvd() override;

            // Child should access each PacketBuffer directly:
            satcat5::io::PacketBuffer m_tx; // Transmit data (user writes, child reads)
            satcat5::io::PacketBuffer m_rx; // Receive data  (user reads, child writes)
        };

        // BufferedCopy copies from any Readable source to any Writeable sink.
        // To use: Pass the source and sink pointers to the constructor. Work
        //         is performed during satcat5::poll::service().
        class BufferedCopy final
            : protected satcat5::io::EventListener
        {
        public:
            BufferedCopy(
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst);
            ~BufferedCopy() SATCAT5_OPTIONAL_DTOR;

        protected:
            void data_rcvd() override;

            satcat5::io::Readable*  m_src;
            satcat5::io::Writeable* m_dst;
        };

        // BufferedWriter adds an inline buffer to any Writeable interface.
        // To use: Pass the next-hop Writeable pointer to the constructor,
        //         and write all data to the BufferedWriter object.
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
