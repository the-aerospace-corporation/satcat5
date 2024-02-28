//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// BufferedIO wrapper for two-way UDP communication

#pragma once

#include <satcat5/net_socket.h>
#include <satcat5/udp_core.h>
#include <satcat5/udp_dispatch.h>

// Default size parameters for the fixed-size buffer.
// Override with a larger buffer size to support jumbo Ethernet+UDP frames.
// (i.e., Add gcc argument "-DSATCAT5_UDP_BUFFSIZE=16384" etc.)
// The default is large enough for any regular Ethernet+UDP frame.
#ifndef SATCAT5_UDP_BUFFSIZE
#define SATCAT5_UDP_BUFFSIZE   1600     // One full-size UDP frame
#endif

#ifndef SATCAT5_UDP_PACKETS
#define SATCAT5_UDP_PACKETS    32       // ...or many smaller frames
#endif

namespace satcat5 {
    namespace udp {
        // Core functionality with DIY memory allocation.
        class SocketCore
            : public satcat5::udp::AddressContainer
            , public satcat5::net::SocketCore
        {
        public:
            // Listening mode only (no remote address).
            void bind(const satcat5::udp::Port& port);

            // Manual address resolution (user supplies IP + MAC)
            // Note: If source port is not specified, assign any free port index.
            void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::eth::MacAddr& dstmac,
                const satcat5::udp::Port& dstport,
                satcat5::udp::Port srcport = satcat5::udp::PORT_NONE);

            // Automatic address resolution (user supplies IP + gateway)
            // (See "ip_core.h / ip::Address" for more information.
            // Note: If source port is not specified, assign any free port index.
            void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport,
                satcat5::udp::Port srcport = satcat5::udp::PORT_NONE);

            // Retry automatic address resolution.
            void reconnect() {m_addr.retry();}

            // Useful inherited methods from net::SocketCore:
            //  close(), ready_rx(), ready_tx()

        protected:
            SocketCore(
                satcat5::udp::Dispatch* iface,
                u8* txbuff, unsigned txbytes, unsigned txpkt,
                u8* rxbuff, unsigned rxbytes, unsigned rxpkt);
            ~SocketCore() {}
        };

        // Wrapper with a fixed-size buffer.
        class Socket final : public satcat5::udp::SocketCore {
        public:
            explicit Socket(satcat5::udp::Dispatch* iface);
            ~Socket() {}

            // Useful inherited methods from udp::SocketCore:
            //  bind(...), connect(...), close(), ready_rx(), ready_tx()

        private:
            u8 m_txbuff[SATCAT5_UDP_BUFFSIZE];
            u8 m_rxbuff[SATCAT5_UDP_BUFFSIZE];
        };
    }
}
