//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_address.h>
#include <satcat5/ip_dispatch.h>

using satcat5::eth::MACADDR_BROADCAST;
using satcat5::eth::MACADDR_NONE;
using satcat5::eth::MacAddr;
using satcat5::eth::VlanTag;
using satcat5::eth::VTAG_NONE;
using satcat5::ip::Addr;
using satcat5::ip::Address;
using satcat5::ip::Dispatch;
namespace ip = satcat5::ip;

// Set default rate-limiter for outgoing ARP requests?
// (i.e., Minimum time between requests, in milliseconds.)
#ifndef SATCAT5_ARP_RETRY_MSEC
#define SATCAT5_ARP_RETRY_MSEC 100
#endif

Address::Address(Dispatch* iface, u8 proto)
    : m_iface(nullptr)
    , m_proto(proto)
    , m_ready(0)
    , m_arp_tref(SATCAT5_CLOCK->now())
    , m_dstmac(MACADDR_BROADCAST)
    , m_dstaddr(ip::ADDR_NONE)
    , m_gateway(ip::ADDR_NONE)
    , m_vtag(VTAG_NONE)
{
    init(iface);
}

#if SATCAT5_ALLOW_DELETION
Address::~Address() {
    if (m_iface) m_iface->m_arp.remove(this);
}
#endif

void Address::init(Dispatch* iface) {
    if (iface && !m_iface) {
        m_iface = iface;
        m_iface->m_arp.add(this);
    }
}

void Address::connect(const Addr& dstaddr, const VlanTag& vtag) {
    if (!m_iface) return;

    // Set destination MAC to a placeholder for now.
    auto route  = m_iface->route_lookup(dstaddr);
    m_dstaddr   = dstaddr;
    m_dstmac    = route.dstmac;
    m_gateway   = route.gateway;
    m_vtag      = vtag;
    m_arp_tref  = SATCAT5_CLOCK->now();

    // Do we need to issue an ARP query?
    if (m_gateway.is_multicast() || m_dstmac.is_unicast()) {
        m_ready = 1;    // Cached or multicast MAC address = Ready
    } else if (m_gateway.is_unicast()) {
        m_ready = 0;    // Unknown MAC = Start ARP query
        m_iface->m_arp.send_query(m_gateway);
    } else {
        m_ready = 0;    // Invalid IP = Halt
    }
}

void Address::connect(const Addr& dstaddr, const MacAddr& dstmac, const VlanTag& vtag) {
    // User has provided all required parameters.
    // Note: DHCP requires dstaddr = 0 for some edge-cases.
    m_dstmac    = dstmac;
    m_dstaddr   = dstaddr;
    m_gateway   = ip::ADDR_NONE;
    m_vtag      = vtag;
    m_ready     = (dstmac != MACADDR_NONE) ? 1 : 0;
}

void Address::retry() {
    // Retry ARP query (automatic address resolution only).
    if (m_iface && !m_ready) {
        m_iface->m_arp.send_query(m_gateway, m_vtag);
    }
}

void Address::close() {
    m_dstmac    = MACADDR_BROADCAST;
    m_dstaddr   = ip::ADDR_NONE;
    m_gateway   = ip::ADDR_NONE;
    m_ready     = 0;
}

satcat5::net::Dispatch* Address::iface() const
    {return m_iface;}

satcat5::io::Writeable* Address::open_write(unsigned len) {
    if (m_ready) {
        // Send the IP packet.
        return m_iface->open_write(m_dstmac, m_vtag, m_dstaddr, m_proto, len);
    } else if (m_iface && m_arp_tref.interval_msec(SATCAT5_ARP_RETRY_MSEC)) {
        // If we haven't gotten an ARP reply, try again subject to rate-limit.
        m_iface->m_arp.send_query(m_gateway, m_vtag);
    }
    return 0;   // Unable to send.
}

bool Address::is_multicast() const {
    return m_dstaddr.is_multicast();
}

bool Address::matches_reply_address() const {
    if (!m_iface) return false;
    bool eth_match = m_dstmac.is_multicast() || m_dstmac == m_iface->reply_mac();
    bool ip_match  = m_dstaddr.is_multicast() || m_dstaddr == m_iface->reply_ip();
    bool vid_match = m_iface->reply_vtag().vid() == m_vtag.vid();
    return eth_match && ip_match && vid_match;
}

bool Address::reply_is_multicast() const {
    return m_iface && m_iface->reply_is_multicast();
}

void Address::save_reply_address() {
    if (m_iface) {
        m_dstmac    = m_iface->reply_mac();
        m_dstaddr   = m_iface->reply_ip();
        m_gateway   = ip::ADDR_NONE;
        m_ready     = 1;
    }
}

void Address::arp_event(const MacAddr& mac, const Addr& ip) {
    // If we get a match, update the stored MAC address.
    if (ip == m_gateway) {
        m_dstmac    = mac;
        m_ready     = 1;
    }
}

void Address::gateway_change(const Addr& dstaddr, const Addr& gateway) {
    // Is this redirect relevant to our destination address?
    if ((dstaddr == m_dstaddr) && (gateway != m_gateway)) {
        // Immediately update the next-hop gateway address.
        m_gateway = gateway;
        // Is the new gateway in our MAC address cache?
        // Otherwise, initiate an ARP query.
        auto route = m_iface->route_lookup(dstaddr);
        if (route.dstmac.is_valid()) m_dstmac = route.dstmac;
        else m_iface->m_arp.send_query(m_gateway);
        // In either case, keep the socket open and ready. The previous
        // gateway can keep forwarding packets until we get an ARP response.
    }
}
