//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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
