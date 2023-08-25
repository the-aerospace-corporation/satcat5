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

#include <satcat5/ip_dispatch.h>
#include <satcat5/log.h>

using satcat5::eth::ETYPE_IPV4;
using satcat5::ip::Dispatch;
using satcat5::net::Type;
namespace ip    = satcat5::ip;
namespace log   = satcat5::log;

// Set verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// Time To Live (TTL) sets maximum number of hops.
#ifndef SATCAT5_IP_TTL
#define SATCAT5_IP_TTL 128
#endif

Dispatch::Dispatch(
        const ip::Addr& addr,
        satcat5::eth::Dispatch* iface,
        satcat5::util::GenericTimer* timer)
    : satcat5::net::Protocol(Type(ETYPE_IPV4.value))
    , m_timer(timer)
    , m_arp(iface, addr)
    , m_icmp(this)
    , m_iface(iface)
    , m_addr(addr)
    , m_reply_ip(ip::ADDR_NONE)
    , m_ident(0)
    , m_route_count(0)
    , m_route_default(addr)
{
    m_iface->add(this);
}

#if SATCAT5_ALLOW_DELETION
Dispatch::~Dispatch()
{
    m_iface->remove(this);
}
#endif

satcat5::io::Writeable* Dispatch::open_reply(
    const satcat5::net::Type& type, unsigned len)
{
    return open_write(m_iface->reply_mac(), m_reply_ip, type.as_u8(), len);
}

satcat5::io::Writeable* Dispatch::open_write(
    const satcat5::eth::MacAddr& mac,   // Destination MAC
    const ip::Addr& dst,                // Destination IP
    u8 protocol,                        // Protocol (UDP/TCP/etc)
    unsigned len)                       // Length after IP header
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "IpDispatch: open_write");

    // Write the Ethernet frame header.
    satcat5::io::Writeable* wr = m_iface->open_write(mac, ETYPE_IPV4);
    if (!wr) return 0;                  // Unable to proceed

    // TTL + protocol word puts TTL in MSBs.
    u16 ttl_word = 256 * SATCAT5_IP_TTL + protocol;
    u16 len_total = (u16)(len + ip::HDR_MIN_BYTES);

    // Populate header fields so we can calculate checksum.
    u16 hdr[ip::HDR_MIN_SHORTS];
    hdr[0] = 0x4500;                    // Version (4) + IHL (5 wds) + No DSCP/ECN
    hdr[1] = len_total;                 // Total packet length (incl header)
    hdr[2] = m_ident++;                 // Identification = sequential counter
    hdr[3] = 0;                         // No fragmentation when sending
    hdr[4] = ttl_word;                  // TTL + Protocol (see above)
    hdr[5] = 0;                         // Placeholder for checksum
    hdr[6] = (u16)(m_addr.value >> 16); // Source IP (MSW then LSW)
    hdr[7] = (u16)(m_addr.value >> 0);
    hdr[8] = (u16)(dst.value >> 16);    // Destination IP (MSW then LSW)
    hdr[9] = (u16)(dst.value >> 0);

    // Calculate checksum using method from RFC 1071 Section 4.1.
    hdr[5] = ip::checksum(ip::HDR_MIN_SHORTS, hdr);
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "IpDispatch: header chk").write(hdr[5]);

    // Write the IPv4 header before handing off to user.
    for (unsigned a = 0 ; a < ip::HDR_MIN_SHORTS ; ++a)
        wr->write_u16(hdr[a]);          // Convert each field to network order
    return wr;                          // Ready to write frame contents
}

void Dispatch::set_addr(const ip::Addr& addr)
{
    m_addr = addr;
    m_arp.set_ipaddr(addr);
}

void Dispatch::route_clear()
{
    m_route_count = 0;                  // Discard all table entries
    m_route_default = m_addr;           // Self-default = Assume local
}

void Dispatch::route_default(const ip::Addr& gateway)
{
    m_route_default = gateway;
}

void Dispatch::route_simple(const ip::Addr& gateway, const ip::Mask& subnet)
{
    ip::Subnet local = {m_addr, subnet};
    route_clear();                      // Clear existing table contents.
    route_default(gateway);             // Default gateway for everything...
    route_set(local, m_addr);           // ...except local connections.
}

bool Dispatch::route_set(const ip::Subnet& subnet, const ip::Addr& gateway)
{
    // Are we trying to set the default route?
    if (subnet == ip::DEFAULT_ROUTE) {
        m_route_default = gateway;
        return true;        // Success!
    }

    // Is this an update to an existing route?
    for (u16 a = 0 ; a < m_route_count ; ++a) {
        if (subnet == m_route_table[a].subnet) {
            m_route_table[a].gateway = gateway;
            return true;    // Success!
        }
    }

    // Attempt to add a new table entry.
    if (m_route_count < SATCAT5_ROUTING_TABLE) {
        m_route_table[m_route_count++] = {subnet, gateway};
        return true;        // Success!
    } else {
        return false;       // Table is full.
    }
}

ip::Addr Dispatch::route_lookup(const ip::Addr& dstaddr) const
{
    // Ignore queries for multicast addresses.
    if (dstaddr.is_multicast()) return dstaddr;

    // Iterate over the table to find the narrowest match.
    // Note: A narrow mask (e.g., /24 = 0xFFFFFF00) is numerically
    //   greater than a wide mask (e.g., /8 = 0xFF000000).
    ip::Mask mask = ip::MASK_NONE;
    ip::Addr next = m_route_default;
    for (u16 a = 0 ; a < m_route_count ; ++a) {
        if (m_route_table[a].subnet.mask.value > mask.value &&
            m_route_table[a].subnet.contains(dstaddr)) {
            mask = m_route_table[a].subnet.mask;
            next = m_route_table[a].gateway;
        }
    }

    // Local hops (i.e., next = self) route directly to the destination.
    if (next == m_addr) next = dstaddr;
    return next;
}

void Dispatch::frame_rcvd(satcat5::io::LimitedRead& rd)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "IpDispatch: frame_rcvd").write((u16)rd.get_read_ready());

    // Sanity check before we start.
    if (rd.get_read_ready() < ip::HDR_MIN_BYTES) return;

    // Read the baseline header.
    for (unsigned a = 0 ; a < ip::HDR_MIN_SHORTS ; ++a)
        m_reply_hdr.data[a] = rd.read_u16();

    // Parse various header fields...
    const u16* hdr = m_reply_hdr.data;
    unsigned ver = (hdr[0] >> 12) & 0x0F;   // Version
    unsigned ihl = (hdr[0] >>  8) & 0x0F;   // Header length (words)
    unsigned rem = 4 * (ihl - 5);           // Extra header bytes
    unsigned len = hdr[1] - 4 * ihl;        // User data length
    unsigned frg = hdr[3] & 0xBFFF;         // Fragments (ignore DF bit)
    u8 proto = hdr[4] & 0x00FF;             // Protocol (UDP/TCP/etc.)
    ip::Addr src(hdr[6], hdr[7]);           // Source IP
    ip::Addr dst(hdr[8], hdr[9]);           // Destination IP

    // Sanity-check various header fields.
    // TODO: Add support for fragmentation?
    if ((ver != 4) || (ihl < 5)) return;            // Unsupported version?
    if (rd.get_read_ready() < rem + len) return;    // Remaining length OK?
    if (frg) return;                                // Fragmentation? (Not supported)

    // Is this packet actually intended for us?
    bool accept = (dst == m_addr)           // Regular unicast
        || (dst.is_multicast())             // Broadcast or multicast
        || (m_addr == ip::ADDR_NONE);       // Local address not (yet) set
    if (!accept) return;

    // Read extended header options, if any.
    // (Required for checksum, ICMP echo requests, etc.)
    for (unsigned a = ip::HDR_MIN_SHORTS ; a < 2*ihl ; ++a)
        m_reply_hdr.data[a] = rd.read_u16();

    // Verify checksum over entire header, using algorithm from RFC 1071.
    u16 chk = ip::checksum(2*ihl, m_reply_hdr.data);
    if (chk != 0) {
        if (DEBUG_VERBOSE > 0)
            log::Log(log::INFO, "IpDispatch: Bad checksum").write(chk);
        return;
    } else if (DEBUG_VERBOSE > 1) {
        log::Log(log::DEBUG, "IpDispatch: Checksum OK");
    }

    // Deliver packet to the appropriate handler (ICMP/UDP/TCP/etc.)
    m_reply_ip = {src};
    bool ok = deliver(Type(proto), &rd, len);

    // Send an ICMP "Protocol unreachable" error?
    if (!ok) m_icmp.send_error(ICMP_UNREACHABLE_PROTO, &rd);
}
