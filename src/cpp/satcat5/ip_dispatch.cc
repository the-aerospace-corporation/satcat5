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
    , m_addr(addr)
    , m_timer(timer)
    , m_arp(iface, addr)
    , m_icmp(this)
    , m_iface(iface)
    , m_reply_ip(ip::ADDR_NONE)
    , m_ident(0)
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
    const ip::Addr& ip,                 // Destination IP
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
    hdr[8] = (u16)(ip.value >> 16);     // Destination IP (MSW then LSW)
    hdr[9] = (u16)(ip.value >> 0);

    // Calculate checksum using method from RFC 1071 Section 4.1.
    hdr[5] = ip::checksum(ip::HDR_MIN_SHORTS, hdr);
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "IpDispatch: header chk").write(hdr[5]);

    // Write the IPv4 header before handing off to user.
    for (unsigned a = 0 ; a < ip::HDR_MIN_SHORTS ; ++a)
        wr->write_u16(hdr[a]);          // Convert each field to network order
    return wr;                          // Ready to write frame contents
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
    if (!(dst == m_addr || dst.is_multicast())) return;

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
