//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2023 The Aerospace Corporation
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
//
// The IP dispatch subsystem must be attached to an Ethernet interface,
// accepting all incoming traffic with EtherType 0x0800 (IPv4).  Incoming
// packets are checked for validity and then sorted by IP protocol number
// (i.e., ICMP, UDP, TCP, etc.).
//
// The system includes static routing tables for next-hop routing.
// By default, all routes are assumed to be local (i.e., the next hop
// is the final destination with no intermediate routers).  To change
// this behavior, call the route_** methods to fill the routing table.
// A shortcut "route_simple(...)" is provided for configuring simple
// networks that have a single access point.
//
// For an all-in-one container with ip::Dispatch and other components
// required for UDP communications, use ip::Stack (ip_stack.h).
//

#pragma once

#include <satcat5/eth_arp.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/ip_core.h>
#include <satcat5/ip_icmp.h>
#include <satcat5/net_core.h>

// Set size of the static routing table, not including the default route.
// (To override, add gcc argument "-DSATCAT5_UDP_BUFFSIZE=32" etc.)
#ifndef SATCAT5_ROUTING_TABLE
#define SATCAT5_ROUTING_TABLE 4
#endif

namespace satcat5 {
    namespace ip {
        // Implemention of "net::Dispatch" for IPv4 frames.
        class Dispatch final
            : public satcat5::net::Protocol
            , public satcat5::net::Dispatch
        {
        public:
            // Constructor requires the local address (may be ADDR_NONE),
            // an Ethernet interface, and a time reference.  The address
            // may be changed later if desired.
            Dispatch(
                const satcat5::ip::Addr& addr,
                satcat5::eth::Dispatch* iface,
                satcat5::util::GenericTimer* timer);
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            // Get Writeable object for deferred write of IPv4 frame header.
            // Variants for reply (required) or a specific address (optional).
            satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned len) override;
            satcat5::io::Writeable* open_write(
                const satcat5::eth::MacAddr& mac,   // Destination MAC
                const satcat5::ip::Addr& ip,        // Destination IP
                u8 protocol,                        // Protocol (UDP/TCP/etc)
                unsigned len);                      // Length after IP header

            // Set the local IP-address.
            void set_addr(const satcat5::ip::Addr& addr);

            // Clear ALL routes, including the default.
            // (This configuration assumes all connections are local ones.)
            void route_clear();

            // Set the default route.  Setting the default to ADDR_NONE
            // causes any connection to fail unless defined explicitly.
            void route_default(
                const satcat5::ip::Addr& gateway);

            // Simplified one-step setup for a typical home network.
            // (i.e., A small LAN with a single gateway router.)
            void route_simple(
                const satcat5::ip::Addr& gateway,
                const satcat5::ip::Mask& subnet = satcat5::ip::MASK_24);

            // Create or update a single route.
            // Returns true if successful, false if table is full.
            bool route_set(
                const satcat5::ip::Subnet& subnet,
                const satcat5::ip::Addr& gateway);

            // Next-hop routing lookup for the given destination address.
            satcat5::ip::Addr route_lookup(
                const satcat5::ip::Addr& dstaddr) const;

            // Other accessors:
            inline satcat5::eth::ProtoArp* arp()
                {return &m_arp;}
            inline satcat5::eth::Dispatch* iface() const
                {return m_iface;}
            inline satcat5::ip::Addr ipaddr() const
                {return m_addr;}
            inline satcat5::eth::MacAddr macaddr() const
                {return m_iface->m_addr;}
            inline satcat5::eth::MacAddr reply_mac() const
                {return m_iface->reply_mac();}
            inline satcat5::ip::Addr reply_ip() const
                {return m_reply_ip;}
            inline const satcat5::ip::Header& reply_hdr() const
                {return m_reply_hdr;}

            // Reference timer (for ICMP timestamps, etc.)
            satcat5::util::GenericTimer* const m_timer;

            // ARP and ICMP handlers for this interface.
            satcat5::eth::ProtoArp m_arp;
            satcat5::ip::ProtoIcmp m_icmp;

        protected:
            // A single entry in the static routing table.
            struct Route {
                satcat5::ip::Subnet subnet;
                satcat5::ip::Addr   gateway;
            };

            // Event handler for incoming IPv4 frames.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Pointer to the parent interface.
            satcat5::eth::Dispatch* const m_iface;

            // IP address for this interface.
            satcat5::ip::Addr m_addr;

            // The current reply state (address + complete header).
            satcat5::ip::Addr m_reply_ip;
            satcat5::ip::Header m_reply_hdr;

            // Identification field for outgoing packets.
            u16 m_ident;

            // Static routing table.
            u16 m_route_count;
            satcat5::ip::Addr m_route_default;
            satcat5::ip::Dispatch::Route m_route_table[SATCAT5_ROUTING_TABLE];
        };
    }
}
