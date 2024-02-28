//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_address.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/ip_icmp.h>
#include <satcat5/log.h>
#include <satcat5/timer.h>

// Enable more detailed ICMP error messages?
// Disabling this feature can save some code-size.
#ifndef SATCAT5_ICMP_DETAIL
#define SATCAT5_ICMP_DETAIL 1   // Level of detail (0/1/2)
#endif

using satcat5::ip::ProtoIcmp;
using satcat5::net::Type;
namespace ip  = satcat5::ip;
namespace log = satcat5::log;

// Dispatch type codes.
static constexpr Type TYPE_ICMP = Type(ip::PROTO_ICMP);

// ICMP timestamps use MSB to indicate format:
//  '0' = Milliseconds since midnight
//  '1' = Any other format
static constexpr u32 TIMESTAMP_ARB = (1u << 31);

// Length of various message types.
static constexpr unsigned ECHO_WORDS = 4;
static constexpr unsigned TIME_WORDS = 10;

// Translate ICMP type-code to a human-readable error message, if applicable.
inline const char* code2msg(u16 code)
{
    if (SATCAT5_ICMP_DETAIL >= 2) {
        // Full error for less-common messages.
        if (code == ip::ICMP_FRAG_REQUIRED)
            return "Fragmentation required but DF set";
        if (code == ip::ICMP_SRC_ROUTE_FAILED)
            return "Source route failed";
        if (code == ip::ICMP_DST_NET_UNKNOWN)
            return "Destination network unknown";
        if (code == ip::ICMP_DST_HOST_UNKNOWN)
            return "Destination host unknown";
        if (code == ip::ICMP_SRC_HOST_ISOLATED)
            return "Source host isolated";
        if (code == ip::ICMP_NET_PROHIBITED)
            return "Network administratively prohibited";
        if (code == ip::ICMP_HOST_PROHIBITED)
            return "Host administratively prohibited";
        if (code == ip::ICMP_TOS_NET)
            return "Network unreachable for ToS";
        if (code == ip::ICMP_TOS_HOST)
            return "Host unreachable for ToS";
        if (code == ip::ICMP_COMM_PROHIBITED)
            return "Communication administratively prohibited";
        if (code == ip::ICMP_HOST_PRECEDENCE)
            return "Host precedence violation";
        if (code == ip::ICMP_PRECEDENCE_CUTOFF)
            return "Precedence cutoff in effect";
        if (code == ip::ICMP_FRAG_TIMEOUT)
            return "Fragment reassembly time exceeded";
        if (code == ip::ICMP_IP_HDR_POINTER)
            return "IP Header: Pointer error";
        if (code == ip::ICMP_IP_HDR_OPTION)
            return "IP Header: Missing required option";
        if (code == ip::ICMP_IP_HDR_LENGTH)
            return "IP Header: Bad length";
    }

    if (SATCAT5_ICMP_DETAIL >= 1) {
        // Full error for common messages.
        if (code == ip::ICMP_UNREACHABLE_NET)
            return "Destination network unreachable";
        if (code == ip::ICMP_UNREACHABLE_HOST)
            return "Destination host unreachable";
        if (code == ip::ICMP_UNREACHABLE_PROTO)
            return "Destination protocol unreachable";
        if (code == ip::ICMP_UNREACHABLE_PORT)
            return "Destination port unreachable";
        if (code == ip::ICMP_TTL_EXPIRED)
            return "TTL expired in transit";
    }

    // Catch-all for broad error categories.
    u16 type = code & ip::ICMP_TYPE_MASK;
    if (type == ip::ICMP_TYPE_UNREACHABLE)
        return "Destination unreachable";
    if (type == ip::ICMP_TYPE_TIME_EXCEED)
        return "Time exceeded";
    if (type == ip::ICMP_TYPE_BAD_IP_HDR)
        return "IP header error";

    // Ignore all other messages.
    return 0;
}

ProtoIcmp::ProtoIcmp(ip::Dispatch* iface)
    : satcat5::net::Protocol(TYPE_ICMP)
    , m_iface(iface)
{
    m_iface->add(this);
}

#if SATCAT5_ALLOW_DELETION
ProtoIcmp::~ProtoIcmp()
{
    m_iface->remove(this);
}
#endif

bool ProtoIcmp::send_error(u16 type, satcat5::io::Readable* src, u32 arg)
{
    // ICMP error messages always include:
    //  u16     Typecode
    //  u16     Checksum
    //  u32     Argument / unused (varies)
    //  Varies  IPv4 header (max 30 x uint16)
    //  4 x u16 First 8 bytes from datagram
    // This gives a total worst-case length of 38 x uint16.
    u16 buff[ip::HDR_MAX_SHORTS + 8];

    // Get header from the packet that triggered this error.
    const ip::Header& hdr = m_iface->reply_hdr();

    // Start populating the message fields:
    u16* ptr = buff;
    (*ptr++) = type;                    // Message type
    (*ptr++) = 0;                       // Placeholder for checksum
    (*ptr++) = (u16)(arg >> 16);        // Special argument (varies)
    (*ptr++) = (u16)(arg >> 0);         // Special argument (varies)
    for (unsigned a = 0 ; a < 2 * hdr.ihl() ; ++a)
        (*ptr++) = hdr.data[a];         // Copy the original IPv4 header
    for (unsigned a = 0 ; a < 4 ; ++a)
        (*ptr++) = src->read_u16();     // Copy first 8 bytes of user data

    // Open a stream and send the error message.
    unsigned wcount = ptr - buff;   // Length (16-bit words)
    satcat5::io::Writeable* wr = m_iface->open_reply(TYPE_ICMP, 2*wcount);
    return write_icmp(wr, wcount, buff);
}

bool ProtoIcmp::send_ping(ip::Address& dst)
{
    // Embed current time in the request packet.
    u32 now = m_iface->m_timer->now();

    // Formulate the ICMP echo request:
    u16 buff[ECHO_WORDS];
    buff[0] = ip::ICMP_ECHO_REQUEST;    // Message type
    buff[1] = 0;                        // Placeholder for checksum
    buff[2] = (u16)(now >> 16);         // Timestamp (MSBs)
    buff[3] = (u16)(now >>  0);         // Timestamp (LSBs)

    // Open a stream and send the echo-request message.
    satcat5::io::Writeable* wr = dst.open_write(2*ECHO_WORDS);
    return write_icmp(wr, ECHO_WORDS, buff);
}

bool ProtoIcmp::send_timereq(ip::Address& dst)
{
    // "Originate" timestamp uses the arbitrary-units flag.
    u32 now = m_iface->m_timer->now() | TIMESTAMP_ARB;

    // Formulate the timestamp request:
    u16 buff[TIME_WORDS];
    buff[0] = ip::ICMP_TIME_REQUEST;    // Message type
    buff[1] = 0;                        // Placeholder for checksum
    buff[2] = 0xDEAD;                   // Identifier (unused)
    buff[3] = 0xBEEF;                   // Sequence (unused)
    buff[4] = (u16)(now >> 16);         // Timestamp (MSBs)
    buff[5] = (u16)(now >>  0);         // Timestamp (LSBs)
    buff[6] = 0;                        // Zero-pad placeholders
    buff[7] = 0;
    buff[8] = 0;
    buff[9] = 0;

    // Open a stream and send the echo-request message.
    satcat5::io::Writeable* wr = dst.open_write(2*TIME_WORDS);
    return write_icmp(wr, TIME_WORDS, buff);
}

void ProtoIcmp::frame_rcvd(satcat5::io::LimitedRead& src)
{
    // Maximum reply length = N words (arbitrary cutoff).
    // (If an echo attempts to exceed this limit, ignore it.)
    static const unsigned MAX_REPLY = 32;
    static const unsigned MAX_ECHO  = MAX_REPLY - 2;
    u16 buff[MAX_REPLY];

    // Ignore anything that's too short to be a valid packet.
    if (src.get_read_ready() < 8) return;

    // Read the common header.
    u16 code = src.read_u16();              // Message type + code
    src.read_u16();                         // Checksum (discard)
    unsigned wlen = src.get_read_ready() / 2;

    // Handle each supported message type:
    u16 type = code & ip::ICMP_TYPE_MASK;
    auto src_ip  = m_iface->reply_ip();
    if (code == ip::ICMP_ECHO_REPLY) {
        // Ping response: Extract the timestamp we inserted earlier.
        u32 tref = src.read_u32();
        u32 elapsed = m_iface->m_timer->elapsed_usec(tref);
        // Notify listeners of the elapsed round-trip time.
        satcat5::ip::PingListener* item = m_listeners.head();
        while (item) {
            item->ping_event(m_iface->reply_ip(), elapsed);
            item = m_listeners.next(item);
        }
    } else if (code == ip::ICMP_ECHO_REQUEST && wlen <= MAX_ECHO) {
        // Ping request: Copy data from echo request
        buff[0] = ip::ICMP_ECHO_REPLY;      // Message type
        buff[1] = 0;                        // Placeholder for checksum
        for (unsigned a = 0 ; a < wlen ; ++a)
            buff[a+2] = src.read_u16();     // Copy from echo request
        // Open a stream and send the echo-request message.
        unsigned echo_len = wlen + 2;       // Echo data + header
        satcat5::io::Writeable* wr = m_iface->open_reply(TYPE_ICMP, 2*echo_len);
        write_icmp(wr, echo_len, buff);
    } else if (type == ip::ICMP_TYPE_REDIRECT && wlen >= 12) {
        // Redirect: Parse message and forward to ARP handler.
        ip::Addr dstaddr, gateway;
        src.read_obj(gateway);              // First field is the new gateway
        src.read_consume(16);               // Skip ahead to the destination
        src.read_obj(dstaddr);              // Read DST from IPv4 header
        m_iface->m_arp.gateway_change(dstaddr, gateway);
    } else if (code == ip::ICMP_TIME_REPLY && wlen >= 8) {
        // Timestamp response: Log but take no further action.
        src.read_consume(12);               // Skip unused information
        u32 stamp = src.read_u32();         // Read transmit timestamp
        log::Log(log::INFO, "Timestamp response").write(stamp);
    } else if (code == ip::ICMP_TIME_REQUEST && wlen >= 8) {
        // Timestamp request: Reply uses the arbitrary-units flag.
        u32 now = m_iface->m_timer->now() | TIMESTAMP_ARB;
        // Construct and send the timestamp response (10 words).
        buff[0] = ip::ICMP_TIME_REPLY;      // Message type
        buff[1] = 0;                        // Placeholder for checksum
        buff[2] = src.read_u16();           // Echo ID
        buff[3] = src.read_u16();           // Echo Seq
        buff[4] = src.read_u16();           // Echo timestamp (MSBs)
        buff[5] = src.read_u16();           // Echo timestamp (LSBs)
        buff[6] = (u16)(now >> 16);         // Receive timestamp
        buff[7] = (u16)(now >>  0);         // Receive timestamp
        buff[8] = (u16)(now >> 16);         // Transmit timestamp
        buff[9] = (u16)(now >>  0);         // Transmit timestamp
        // Open a stream and send the timestamp-reply message.
        satcat5::io::Writeable* wr = m_iface->open_reply(TYPE_ICMP, 2*TIME_WORDS);
        write_icmp(wr, TIME_WORDS, buff);
    } else {
        // Log the error message, if any (varying verbosity options)
        const char* msg = code2msg(code);
        if (msg) {log::Log(log::WARNING, msg).write(src_ip);}
    }
}

bool ProtoIcmp::write_icmp(
    satcat5::io::Writeable* wr,
    unsigned wcount, u16* data)
{
    // Sanity check that the output stream is OK.
    if (!wr) return false;

    // ICMP checksum is always placed at the same offset.
    data[1] = ip::checksum(wcount, data);

    // Write frame contents to the designated buffer.
    for (unsigned a = 0 ; a < wcount ; ++a)
        wr->write_u16(data[a]);
    return wr->write_finalize();
}
