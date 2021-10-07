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
// Protocol handler and dispatch unit for Internet Protocol v4 (IPv4)

#pragma once

#include <satcat5/eth_arp.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/ip_core.h>
#include <satcat5/ip_icmp.h>
#include <satcat5/net_core.h>

namespace satcat5 {
    namespace ip {
        // Implemention of "net::Dispatch" for IPv4 frames.
        class Dispatch final
            : public satcat5::net::Protocol
            , public satcat5::net::Dispatch
        {
        public:
            Dispatch(
                const satcat5::ip::Addr& addr,
                satcat5::eth::Dispatch* iface,
                satcat5::util::GenericTimer* timer);
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            // Get Writeable object for deferred write of IPv4 frame header.
            // Variants for reply (required) and any address (optional)
            satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned len) override;
            satcat5::io::Writeable* open_write(
                const satcat5::eth::MacAddr& mac,   // Destination MAC
                const satcat5::ip::Addr& ip,        // Destination IP
                u8 protocol,                        // Protocol (UDP/TCP/etc)
                unsigned len);                      // Length after IP header

            // Other accessors:
            inline satcat5::eth::MacAddr reply_mac() const
                {return m_iface->reply_mac();}
            inline satcat5::ip::Addr reply_ip() const
                {return m_reply_ip;}
            inline const satcat5::ip::Header& reply_hdr() const
                {return m_reply_hdr;}

            // IP address for this interface.
            satcat5::ip::Addr const m_addr;

            // Reference timer (for ICMP timestamps, etc.)
            satcat5::util::GenericTimer* const m_timer;

            // ARP and ICMP handlers for this interface.
            satcat5::eth::ProtoArp m_arp;
            satcat5::ip::ProtoIcmp m_icmp;

        protected:
            // Event handler for incoming IPv4 frames.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Pointer to the parent interface.
            satcat5::eth::Dispatch* const m_iface;

            // The current reply state (address + complete header).
            satcat5::ip::Addr m_reply_ip;
            satcat5::ip::Header m_reply_hdr;

            // Identification field for outgoing packets.
            u16 m_ident;
        };
    }
}
