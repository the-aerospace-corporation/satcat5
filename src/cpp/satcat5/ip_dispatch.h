//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Protocol handler and dispatch unit for Internet Protocol v4 (IPv4)

#pragma once

#include <satcat5/eth_arp.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/ip_core.h>
#include <satcat5/ip_icmp.h>
#include <satcat5/ip_table.h>
#include <satcat5/net_core.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace ip {
        //! Protocol handler and dispatch unit for Internet Protocol v4 (IPv4).
        //! This class implements the "net::Dispatch" API for IPv4 frames.
        //!
        //! The IP dispatch subsystem must be attached to an Ethernet interface,
        //! accepting all incoming traffic with EtherType 0x0800 (IPv4).  Incoming
        //! packets are checked for validity and then sorted by IP protocol number
        //! (i.e., ICMP, UDP, TCP, etc.).
        //!
        //! The system includes static routing tables for next-hop routing,
        //! inheriting all functionality from the ip::Table class.
        //!
        //! For an all-in-one container with ip::Dispatch and other components
        //! required for UDP communications, use ip::Stack.
        class Dispatch final
            : public satcat5::eth::ArpListener
            , public satcat5::net::Protocol
            , public satcat5::net::Dispatch
        {
        public:
            //! Link this object to an Ethernet interface.
            //! Constructor requires the local address (may be ADDR_NONE),
            //! an Ethernet interface, and a time reference.  The address
            //! may be changed later if desired.
            Dispatch(
                const satcat5::ip::Addr& addr,
                satcat5::eth::Dispatch* iface,
                satcat5::ip::Table* route);
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            //! Get Writeable object for reply to the last received datagram.
            satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned len) override;

            //! Get Writeable object for sending to a specific IP/MAC address.
            satcat5::io::Writeable* open_write(
                const satcat5::eth::MacAddr& mac,   // Destination MAC
                const satcat5::eth::VlanTag& vtag,  // VLAN information
                const satcat5::ip::Addr& ip,        // Destination IP
                u8 protocol,                        // Protocol (UDP/TCP/etc)
                unsigned len);                      // Length after IP header

            //! Set the local IP-address.
            void set_addr(const satcat5::ip::Addr& addr);

            //! Create a basic IPv4 header with the specified information.
            satcat5::ip::Header next_header(
                u8 protocol,                    // Packet type (ICMP/UDP/etc)
                const satcat5::ip::Addr& dst,   // Destination IP address
                unsigned inner_bytes);          // Length of contained packet

            //! Routing table shortcuts. \see ip_table.h
            //!@{
            inline void route_clear(bool lockdown = true)
                { m_route->route_clear(lockdown); }
            inline bool route_cache(
                const satcat5::ip::Addr& gateway,
                const satcat5::eth::MacAddr& dstmac)
                { return m_route->route_cache(gateway, dstmac); }
            inline bool route_default(
                const satcat5::ip::Addr& gateway,
                const satcat5::eth::MacAddr& dstmac = satcat5::eth::MACADDR_NONE)
                { return m_route->route_default(gateway, dstmac); }
            inline bool route_local(const satcat5::ip::Subnet& subnet)
                { return m_route->route_local(subnet); }
            inline bool route_simple(
                const satcat5::ip::Addr& gateway,
                const satcat5::ip::Mask& subnet = satcat5::ip::MASK_24)
                { return m_route->route_simple(gateway, subnet); }
            inline bool route_static(
                const satcat5::ip::Subnet& subnet,
                const satcat5::ip::Addr& gateway,
                const satcat5::eth::MacAddr& dstmac = satcat5::eth::MACADDR_NONE)
                { return m_route->route_static(subnet, gateway, dstmac); }
            inline bool route_remove(const satcat5::ip::Subnet& subnet)
                { return m_route->route_remove(subnet); }
            inline bool route_remove(const satcat5::ip::Addr& addr)
                { return m_route->route_remove(addr); }
            inline satcat5::ip::Route route_lookup(
                const satcat5::ip::Addr& dstaddr) const
                { return m_route->route_lookup(dstaddr); }
            //!@}

            // Other accessors:
            inline satcat5::eth::ProtoArp* arp()
                { return &m_arp; }
            inline satcat5::ip::ProtoIcmp* icmp()
                { return &m_icmp; }
            inline satcat5::eth::Dispatch* iface() const
                { return m_iface; }
            inline satcat5::ip::Addr ipaddr() const
                { return m_addr; }
            inline satcat5::eth::MacAddr macaddr() const
                { return m_iface->macaddr(); }
            inline satcat5::eth::VlanTag reply_vtag() const
                { return m_iface->reply_vtag(); }
            inline satcat5::eth::MacAddr reply_mac() const
                { return m_iface->reply_mac(); }
            inline bool reply_is_multicast() const
                { return m_reply_dst.is_multicast(); }
            inline satcat5::ip::Addr reply_ip() const
                { return m_reply_src; }
            inline const satcat5::ip::Header& reply_hdr() const
                { return m_reply_hdr; }
            inline void set_ipaddr(const satcat5::ip::Addr& addr)
                { set_addr(addr); }
            inline void set_macaddr(const satcat5::eth::MacAddr& macaddr)
                { m_iface->set_macaddr(macaddr); }
            inline satcat5::ip::Table* table()
                { return m_route; }

            //! For testing purposes only, reset the "ident" field.
            //! (This is unsafe, but simplifies certain unit tests.)
            inline void set_ident(u16 ident)
                { m_ident = ident; }

            // ARP and ICMP handlers for this interface.
            satcat5::eth::ProtoArp m_arp;   //!< DEPRECATED \see arp()
            satcat5::ip::ProtoIcmp m_icmp;  //!< DEPRECATED \see icmp()

        protected:
            // Event handler for the ARP cache.
            void arp_event(
                const satcat5::eth::MacAddr& mac,
                const satcat5::ip::Addr& ip) override;

            // Event handler for incoming IPv4 frames.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Pointer to the parent interface.
            satcat5::eth::Dispatch* const m_iface;
            satcat5::ip::Table* const m_route;

            // IP address for this interface.
            satcat5::ip::Addr m_addr;

            // The current reply state (address + complete header).
            satcat5::ip::Addr m_reply_dst;
            satcat5::ip::Addr m_reply_src;
            satcat5::ip::Header m_reply_hdr;

            // Identification field for outgoing packets.
            u16 m_ident;
        };
    }
}
