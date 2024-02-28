//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_dispatch.h>
#include <satcat5/log.h>
#include <satcat5/udp_dispatch.h>
#include <satcat5/utils.h>

using satcat5::ip::PROTO_UDP;
using satcat5::net::Type;
using satcat5::udp::Dispatch;
namespace log = satcat5::log;

// Set verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// UDP header has a fixed length of 8 bytes (src/dst/len/checksum)
static const unsigned UDP_HDR_LEN   = 8;

// Reserved range for dynamically allocated UDP ports.
static const u16 DYNAMIC_PORT_MIN   = 0xC000;
static const u16 DYNAMIC_PORT_MAX   = 0xFFFF;

Dispatch::Dispatch(satcat5::ip::Dispatch* iface)
    : satcat5::net::Protocol(Type(PROTO_UDP))
    , m_iface(iface)
    , m_next_port(DYNAMIC_PORT_MIN - 1)
    , m_reply_src(satcat5::udp::PORT_NONE)
    , m_reply_dst(satcat5::udp::PORT_NONE)
{
    m_iface->add(this);
}

#if SATCAT5_ALLOW_DELETION
Dispatch::~Dispatch()
{
    m_iface->remove(this);
}
#endif

satcat5::udp::Port Dispatch::next_free_port()
{
    // Increment previous port iteration and check for prior claims.
    // (Inspired by lwIP; succeeds on the first try 99% of the time.)
    // Keep trying until we find a free port or we're back where we started.
    u16 wrap = m_next_port;
    while (1) {
        // Increment with wraparound.
        m_next_port = (m_next_port < DYNAMIC_PORT_MAX)
            ? (m_next_port + 1) : (DYNAMIC_PORT_MIN);
        // Check if current hypothesis is free.
        if (!bound(Type(m_next_port)))
            return satcat5::udp::Port(m_next_port);
        // Abort if we've searched the entire range.
        if (m_next_port == wrap) {
            log::Log(log::WARNING, "UdpDispatch: Ports full");
            return satcat5::udp::PORT_NONE;
        }
    }
}

satcat5::io::Writeable* Dispatch::open_reply(
    const satcat5::net::Type& type, unsigned len)
{
    satcat5::ip::Address addr(m_iface, PROTO_UDP);
    addr.connect(m_iface->reply_ip(), m_iface->reply_mac());

    return open_write(addr,             // Destination IP + MAC
        m_reply_dst,                    // Source and destination ports
        m_reply_src,                    // (Note swap from rcvd packet)
        len);                           // User data length
}

satcat5::io::Writeable* Dispatch::open_write(
    satcat5::ip::Address& addr,         // Destination IP+MAC
    const satcat5::udp::Port& src,      // Source port
    const satcat5::udp::Port& dst,      // Destination port
    unsigned len)                       // User data length
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "UdpDispatch: open_write").write(dst.value);

    // Write out Ethernet and IPv4 headers.
    unsigned total_len = len + UDP_HDR_LEN;
    satcat5::io::Writeable* wr = addr.open_write(total_len);

    // Write the UDP frame header.
    if (wr) {
        wr->write_obj(src);             // Source port
        wr->write_obj(dst);             // Destination port
        wr->write_u16((u16)total_len);  // Length (incl this header)
        wr->write_u16(0);               // Checksum disabled (optional)
    }
    return wr;
}

void Dispatch::frame_rcvd(satcat5::io::LimitedRead& src)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "UdpDispatch: frame_rcvd").write((u16)src.get_read_ready());

    // Sanity-check on length before reading header.
    if (src.get_read_ready() < 8) return;

    // Read the UDP frame header.
    src.read_obj(m_reply_src);      // Source port
    src.read_obj(m_reply_dst);      // Destination port
    u16 len = src.read_u16();       // Frame length (incl this header)
    u16 chk = src.read_u16();       // Checksum (ignored)

    // Sanity-check on the reported length.
    unsigned len_eff = len - UDP_HDR_LEN;
    if ((len < UDP_HDR_LEN) || (len_eff > src.get_read_ready())) {
        if (DEBUG_VERBOSE > 0)
            log::Log(log::INFO, "UdpDispatch: Bad length").write(len);
        return;                     // Invalid length parameter
    }

    // Attempt delivery based on destination port only or source + destination.
    // Use length from UDP header to trim any padding from upper layers.
    Type type1 = Type(m_reply_dst.value);
    Type type2 = Type(m_reply_src.value, m_reply_dst.value);
    bool ok = deliver(type1, &src, len_eff) || deliver(type2, &src, len_eff);

    if (DEBUG_VERBOSE > 0 && !ok)
        log::Log(log::INFO, "UdpDispatch: No such port").write(m_reply_dst.value);
    if (DEBUG_VERBOSE > 1 && ok)
        log::Log(log::DEBUG, "UdpDispatch: Frame delivered").write(m_reply_dst.value);

    // No response to unicast packet? Send an ICMP error message.
    satcat5::ip::Addr dst = m_iface->reply_hdr().dst();
    if (!ok && dst.is_unicast()) {
        // Reconstruct the first N bytes of the original message.
        // (ICMP needs at least 8, which is equal to the UDP header size.)
        u8 temp[satcat5::ip::ICMP_ECHO_BYTES];
        satcat5::io::ArrayWrite wr(temp, sizeof(temp));
        wr.write_obj(m_reply_src);
        wr.write_obj(m_reply_dst);
        wr.write_u16(len);
        wr.write_u16(chk);
        // Forward that data to the ICMP block.
        satcat5::io::ArrayRead rd(temp, sizeof(temp));
        m_iface->m_icmp.send_error(satcat5::ip::ICMP_UNREACHABLE_PORT, &rd);
    }
}
