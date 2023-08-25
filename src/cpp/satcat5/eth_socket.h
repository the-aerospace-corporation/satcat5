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
// BufferedIO wrapper for two-way Ethernet communication

#pragma once

#include <satcat5/ethernet.h>
#include <satcat5/net_socket.h>

// Default size parameters for the fixed-size buffer.
// Override with a larger buffer size to support jumbo Ethernet frames.
// (i.e., Add gcc argument "-DSATCAT5_ESOCK_BUFFSIZE=16384" etc.)
#ifndef SATCAT5_ESOCK_BUFFSIZE
#define SATCAT5_ESOCK_BUFFSIZE   1600   // One full-size Ethernet frame
#endif

#ifndef SATCAT5_ESOCK_PACKETS
#define SATCAT5_ESOCK_PACKETS    32     // ...or many smaller frames
#endif

namespace satcat5 {
    namespace eth {
        // Core functionality with DIY memory allocation.
        class SocketCore
            : public satcat5::eth::AddressContainer
            , public satcat5::net::SocketCore
        {
        public:
            // Listening mode only (no remote address).
            void bind(
                const satcat5::eth::MacType& lcltype,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            // Two-way connection.
            void connect(
                const satcat5::eth::MacAddr& dstmac,
                const satcat5::eth::MacType& dsttype,
                const satcat5::eth::MacType& lcltype = satcat5::eth::ETYPE_NONE,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            // Useful inherited methods from net::SocketCore:
            //  close(), ready_rx(), ready_tx()

        protected:
            SocketCore(
                satcat5::eth::Dispatch* iface,
                u8* txbuff, unsigned txbytes, unsigned txpkt,
                u8* rxbuff, unsigned rxbytes, unsigned rxpkt);
            ~SocketCore() {}
        };

        // Wrapper with a fixed-size buffer.
        class Socket final : public satcat5::eth::SocketCore {
        public:
            Socket(satcat5::eth::Dispatch* iface);
            ~Socket() {}

            // Useful inherited methods from eth::SocketCore:
            //  bind(...), connect(...), close(), ready_rx(), ready_tx()

        private:
            u8 m_txbuff[SATCAT5_ESOCK_BUFFSIZE];
            u8 m_rxbuff[SATCAT5_ESOCK_BUFFSIZE];
        };
    }
}
