//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Buffered wrappers for generic network communication

#pragma once

#include <satcat5/io_buffer.h>
#include <satcat5/net_core.h>

namespace satcat5 {
    namespace net {
        // Buffered I/O for sending and receiving messages.
        class SocketCore
            : public satcat5::io::BufferedIO
            , public satcat5::net::Protocol
        {
        public:
            // Close any open connections.
            void close();

            // Ready to transmit or receive data?
            bool ready_tx() const;
            bool ready_rx() const;

            // Child SHOULD provide suitable "bind" and/or "connect" methods.

        protected:
            // Constructor and destructor are only accessible to child class.
            SocketCore(
                satcat5::net::Address* addr,
                u8* txbuff, unsigned txbytes, unsigned txpkt,
                u8* rxbuff, unsigned rxbytes, unsigned rxpkt);
            ~SocketCore() SATCAT5_OPTIONAL_DTOR;

        private:
            // Required event handlers.
            void data_rcvd() override;
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Generic handler for a specific protocol and address.
            satcat5::net::Address* const m_addr_ptr;
        };
    }
}
