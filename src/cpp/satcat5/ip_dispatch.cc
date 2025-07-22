//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_dispatch.h>
#include <satcat5/log.h>
#include <satcat5/timeref.h>

using satcat5::eth::ETYPE_IPV4;
using satcat5::eth::MacAddr;
using satcat5::ip::Dispatch;
using satcat5::ip::Header;
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
        satcat5::ip::Table* route)
    : Protocol(Type(ETYPE_IPV4.value))
    , m_arp(iface, addr)
    , m_icmp(this)
    , m_iface(iface)
    , m_route(route)
    , m_addr(addr)
    , m_reply_dst(ip::ADDR_NONE)
    , m_reply_src(ip::ADDR_NONE)
    , m_ident(0)
{
    m_arp.add(this);
    m_iface->add(this);

    // For historical reasons, this class seeds the global PRNG.
    satcat5::util::prng.seed(SATCAT5_CLOCK->raw());
    m_ident = u16(satcat5::util::prng.next());
}

#if SATCAT5_ALLOW_DELETION
Dispatch::~Dispatch()
{
    m_arp.remove(this);
    m_iface->remove(this);
}
#endif

satcat5::io::Writeable* Dispatch::open_reply(const Type& type, unsigned len)
{
    return open_write(m_iface->reply_mac(), m_iface->reply_vtag(), m_reply_src, type.as_u8(), len);
}

satcat5::io::Writeable* Dispatch::open_write(
    const satcat5::eth::MacAddr& mac,   // Destination MAC
    const satcat5::eth::VlanTag& vtag,  // VLAN information
    const ip::Addr& dst,                // Destination IP
    u8 protocol,                        // Protocol (UDP/TCP/etc)
    unsigned len)                       // Length after IP header
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "IpDispatch: open_write");

    // Write the Ethernet frame header.
    satcat5::io::Writeable* wr = m_iface->open_write(mac, ETYPE_IPV4, vtag);
    if (!wr) return 0;                  // Unable to proceed?

    // Write the IPv4 header before handing off to user.
    next_header(protocol, dst, len).write_to(wr);
    return wr;                          // Ready for packet contents.
}

void Dispatch::set_addr(const ip::Addr& addr)
{
    m_addr = addr;
    m_arp.set_ipaddr(addr);
}

Header Dispatch::next_header(
    u8 protocol, const ip::Addr& dst, unsigned inner_bytes)
{
    // TTL + protocol word puts TTL in MSBs.
    u16 ttl_word = 256 * SATCAT5_IP_TTL + protocol;
    u16 len_total = (u16)(inner_bytes + ip::HDR_MIN_BYTES);

    // Populate header fields so we can calculate checksum.
    Header hdr;
    hdr.data[0] = 0x4500;           // Version (4) + IHL (5 wds) + No DSCP/ECN
    hdr.data[1] = len_total;        // Total packet length (incl header)
    hdr.data[2] = m_ident++;        // Identification = sequential counter
    hdr.data[3] = 0;                // No fragmentation when sending
    hdr.data[4] = ttl_word;         // TTL + Protocol (see above)
    hdr.data[5] = 0;                // Placeholder for checksum
    hdr.data[6] = (u16)(m_addr.value >> 16); // Source IP (MSW then LSW)
    hdr.data[7] = (u16)(m_addr.value >> 0);
    hdr.data[8] = (u16)(dst.value >> 16);    // Destination IP (MSW then LSW)
    hdr.data[9] = (u16)(dst.value >> 0);

    // Calculate checksum using method from RFC 1071 Section 4.1.
    hdr.data[5] = ip::checksum(ip::HDR_MIN_SHORTS, hdr.data);
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "IpDispatch: header chk").write(hdr.chk());
    return hdr;
}

void Dispatch::arp_event(const MacAddr& mac, const ip::Addr& ip)
{
    // Cache this MAC address in the routing table.
    route_cache(ip, mac);
}

void Dispatch::frame_rcvd(satcat5::io::LimitedRead& rd)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "IpDispatch: frame_rcvd").write((u16)rd.get_read_ready());

    // Attempt to read IPv4 header...
    bool ok = m_reply_hdr.read_from(&rd);
    if (ok && DEBUG_VERBOSE > 1) {
        log::Log(log::DEBUG, "IpDispatch: Header OK");
    } else if (!ok && DEBUG_VERBOSE > 0) {
        log::Log(log::INFO, "IpDispatch: Header error").write(m_reply_hdr.chk());
    }
    if (!ok) return;

    // Ignore fragmented packets (not supported).
    if (m_reply_hdr.frg()) return;

    // Note source and destination address.
    m_reply_dst = m_reply_hdr.dst();
    m_reply_src = m_reply_hdr.src();

    // Check destination. Is this packet intended for us?
    bool accept = (m_reply_dst == m_addr)   // Regular unicast
        || (m_reply_dst.is_multicast())     // Broadcast or multicast
        || (m_addr == ip::ADDR_NONE);       // Local address not (yet) set
    if (!accept) return;

    // Deliver packet to the appropriate handler (ICMP/UDP/TCP/etc.)
    auto typ = Type(m_reply_hdr.proto());
    auto len = m_reply_hdr.len_inner();
    ok = deliver(typ, &rd, len);

    // Send an ICMP "Protocol unreachable" error?
    if (!ok) m_icmp.send_error(ICMP_UNREACHABLE_PROTO, &rd);
}
