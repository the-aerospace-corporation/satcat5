//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
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

#include <satcat5/ip_address.h>
#include <satcat5/ip_dispatch.h>

using satcat5::eth::MACADDR_BROADCAST;
using satcat5::eth::MACADDR_NONE;
using satcat5::eth::MacAddr;
using satcat5::ip::Addr;
using satcat5::ip::Address;
using satcat5::ip::Dispatch;
namespace ip = satcat5::ip;

Address::Address(Dispatch* iface, u8 proto)
    : m_iface(iface)
    , m_proto(proto)
    , m_ready(0)
    , m_dstmac(MACADDR_BROADCAST)
    , m_dstaddr(ip::ADDR_NONE)
    , m_gateway(ip::ADDR_NONE)
{
    // Register for ARP callbacks.
    m_iface->m_arp.add(this);
}

#if SATCAT5_ALLOW_DELETION
Address::~Address()
{
    m_iface->m_arp.remove(this);
}
#endif

void Address::connect(const Addr& dstaddr)
{
    // Set destination MAC to a placeholder for now.
    m_dstmac    = MACADDR_BROADCAST;
    m_dstaddr   = dstaddr;
    m_gateway   = m_iface->route_lookup(dstaddr);

    // Do we need to issue an ARP query?
    if (m_gateway.is_multicast()) {
        m_ready = 1;    // Multicast IP = Broadcast MAC
    } else if (m_gateway != ip::ADDR_NONE) {
        m_ready = 0;    // Unicast IP = Query for MAC
        m_iface->m_arp.send_query(m_gateway);
    } else {
        m_ready = 0;    // Invalid IP = Halt
    }
}

void Address::connect(const Addr& dstaddr, const MacAddr& dstmac)
{
    // User has provided all required parameters.
    // Note: DHCP requires dstaddr = 0 for some edge-cases.
    m_dstmac    = dstmac;
    m_dstaddr   = dstaddr;
    m_gateway   = ip::ADDR_NONE;
    m_ready     = (dstmac != MACADDR_NONE) ? 1 : 0;
}

void Address::retry()
{
    if (!m_ready) {
        m_iface->m_arp.send_query(m_gateway);
    }
}

void Address::close()
{
    m_dstmac    = MACADDR_BROADCAST;
    m_dstaddr   = ip::ADDR_NONE;
    m_gateway   = ip::ADDR_NONE;
    m_ready     = 0;
}

satcat5::net::Dispatch* Address::iface() const
    {return m_iface;}

satcat5::io::Writeable* Address::open_write(unsigned len)
{
    if (!m_ready) {
        // If we haven't gotten an ARP reply, try again.
        // TODO: Add a rate-limiter, timeout, etc. and log the error?
        m_iface->m_arp.send_query(m_gateway);
        return 0;   // Unable to send.
    } else {
        // Send the IP packet.
        return m_iface->open_write(m_dstmac, m_dstaddr, m_proto, len);
    }
}

void Address::arp_event(const MacAddr& mac, const Addr& ip)
{
    // If we get a match, update the stored MAC address.
    if (ip == m_gateway) {
        m_dstmac    = mac;
        m_ready     = 1;
    }
}

void Address::gateway_change(const Addr& dstaddr, const Addr& gateway)
{
    // If we get a redirect, update gateway and send another query.
    // In the meantime, the remote router should be forwarding those packets,
    // so keep sending to that MAC until we get the new ARP response.
    if ((dstaddr == m_dstaddr) && !(gateway == m_gateway)) {
        m_gateway   = gateway;
        m_ready     = 0;
        m_iface->m_arp.send_query(m_gateway);
    }
}
