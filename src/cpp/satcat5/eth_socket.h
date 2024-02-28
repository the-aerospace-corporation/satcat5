//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
