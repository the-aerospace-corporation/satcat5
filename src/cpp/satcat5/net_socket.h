//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Buffered wrappers for generic network communication
//!

#pragma once

#include <satcat5/io_buffer.h>
#include <satcat5/net_core.h>

namespace satcat5 {
    namespace net {
        //! Buffered I/O for sending and receiving messages over a network.
        //! Used for bidirectional communication exchange over a network,
        //! inheriting from io::BufferedIO and net::Protocol to provide Readable
        //! and Writeable interfaces routable from net::Dispatch.
        //! Child SHOULD provide suitable "bind" and/or "connect" methods.
        class SocketCore
            : public satcat5::io::BufferedIO
            , public satcat5::net::Protocol
        {
        public:
            //! Close any open connections.
            void close();

            //! Ready to transmit data?
            bool ready_tx() const;

            //! Ready to receive data?
            bool ready_rx() const;

        protected:
            //! Constructs a SocketCore from a saved net::Address and buffer(s).
            //! Constructor and destructor are only accessible to child class.
            //! The child class provides the working buffers for transmit and
            //! receive data.  Transmit-only or receive-only sockets provide a
            //! null pointer for the unused buffer. \see io::BufferedIO.
            SocketCore(
                satcat5::net::Address* addr,
                u8* txbuff, unsigned txbytes, unsigned txpkt,
                u8* rxbuff, unsigned rxbytes, unsigned rxpkt);

            //! Constructor and destructor are only accessible to child class.
            ~SocketCore() SATCAT5_OPTIONAL_DTOR;

        private:
            //! Required event handlers.
            //! @{
            void data_rcvd(satcat5::io::Readable* src) override;
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            //! @}

            //! Generic handler for a specific protocol and address.
            satcat5::net::Address* const m_addr_ptr;
        };
    }
}
