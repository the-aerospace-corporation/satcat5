//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_arp.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/log.h>

namespace eth   = satcat5::eth;
namespace ip    = satcat5::ip;
namespace log   = satcat5::log;
using satcat5::eth::ArpListener;
using satcat5::eth::ProtoArp;

// Set log verbosity (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// Protocol-related constants:
static const u16 ARP_HTYPE_ETHERNET = 0x0001;
static const u16 ARP_PTYPE_IPV4     = 0x0800;
static const u8  ARP_HLEN_ETHERNET  = 6;
static const u8  ARP_PLEN_IPV4      = 4;
static const u16 ARP_OPER_QUERY     = 0x0001;
static const u16 ARP_OPER_REPLY     = 0x0002;
static const eth::MacAddr MACADDR_ZERO = {0,0,0,0,0,0};

ProtoArp::ProtoArp(
        eth::Dispatch* dispatch,
        const ip::Addr& ipaddr)
    : eth::Protocol(dispatch, eth::ETYPE_ARP)
    , m_ipaddr(ipaddr)
{
    // Nothing else to initialize.
}

bool ProtoArp::send_announce() const
{
    // Psuedo-request method, preferred per RFC5227:
    //  https://datatracker.ietf.org/doc/html/rfc5227#section-3
    return send_internal(
        ARP_OPER_QUERY,                     // ARP query
        eth::MACADDR_BROADCAST,             // Destination = Broadcast
        m_ipaddr,                           // Announce SPA = Our IP
        MACADDR_ZERO,                       // Announce THA = Zero (Required)
        m_ipaddr);                          // Announce TPA = Our IP
}

bool ProtoArp::send_probe(const ip::Addr& target)
{
    // Probe-request method from RFC5227:
    // https://www.rfc-editor.org/rfc/rfc5227#section-2.1
    return send_internal(
        ARP_OPER_QUERY,                     // ARP query
        eth::MACADDR_BROADCAST,             // Destination = Broadcast
        ip::ADDR_NONE,                      // Probe SPA = Zero (Required)
        eth::MACADDR_NONE,                  // Probe THA = Zero (Required)
        target);                            // Probe TPA = Target IP
}

bool ProtoArp::send_query(const ip::Addr& target)
{
    // Send a query for the designated target:
    return send_internal(
        ARP_OPER_QUERY,                     // ARP query
        eth::MACADDR_BROADCAST,             // Destination = Broadcast
        m_ipaddr,                           // Query SPA = Our IP
        eth::MACADDR_BROADCAST,             // Query THA = Placeholder
        target);                            // Query TPA = Target IP
}

void ProtoArp::gateway_change(
    const ip::Addr& dstaddr,
    const ip::Addr& gateway)
{
    ArpListener* item = m_listeners.head();
    while (item) {
        item->gateway_change(dstaddr, gateway);
        item = m_listeners.next(item);
    }
}

void ProtoArp::frame_rcvd(satcat5::io::LimitedRead& src)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "ProtoArp: frame_rcvd");

    // Main "sender" and "target" addresses from the query.
    // (Names match the terms used in IETF RFC 826.)
    eth::MacAddr    sha, tha;       // MAC ("hardware address")
    ip::Addr        spa, tpa;       // IPv4 ("protocol address")

    // Reject anything that's too short to be a valid ARP packet.
    if (src.get_read_ready() < 28)
        return;

    // Read the packet contents:
    // Reference: IETF-RFC-826 https://datatracker.ietf.org/doc/html/rfc826
    // See also: https://en.wikipedia.org/wiki/Address_Resolution_Protocol
    u16 htype   = src.read_u16();   // Hardware type (Ethernet = 1)
    u16 ptype   = src.read_u16();   // Protocol type (IPv4 = 0x0800)
    u8  hlen    = src.read_u8();    // Hardware address length (Ethernet = 6)
    u8  plen    = src.read_u8();    // Protocol address length (IPv4 = 4)
    u16 oper    = src.read_u16();   // Operation (1 = request, 2 = reply)
    src.read_obj(sha);              // Sender hardware address (MAC)
    src.read_obj(spa);              // Sender protocol address (IPv4)
    src.read_obj(tha);              // Target hardware address (MAC)
    src.read_obj(tpa);              // Target protocol address (IPv4)

    // Log the received message?
    if (DEBUG_VERBOSE > 0)
        log::Log(log::INFO, "ProtoArp: Rcvd from").write(spa.value);

    // Ignore anything that's not a IPv4-to-MAC response/query.
    if (htype != ARP_HTYPE_ETHERNET) return;
    if (ptype != ARP_PTYPE_IPV4) return;
    if (hlen != ARP_HLEN_ETHERNET) return;
    if (plen != ARP_PLEN_IPV4) return;

    // Sanity check for valid source addresses.
    if (sha == eth::MACADDR_NONE) return;
    if (sha == eth::MACADDR_BROADCAST) return;

    // Does this query have a valid SHA/SPA pair?
    if (spa.is_unicast()) {
        // Send notifications to any registered ARP event listeners.
        ArpListener* item = m_listeners.head();
        while (item) {
            item->arp_event(sha, spa);
            item = m_listeners.next(item);
        }
    }
    // Note: Replies have a valid THA/TPA pair, but we ignore it.
    //   Normal replies have our own address, which we already know.
    //   Broadcast replies are discouraged by RFC5227.

    // Query for our address? Send a response.
    if ((oper == ARP_OPER_QUERY) && (tpa == m_ipaddr)) {
        // Target is an echo of the SHA/SPA fields from the request.
        // Note: Per RFC5225 Section 2, reply to the requester only.
        if (DEBUG_VERBOSE > 0)
            log::Log(log::DEBUG, "ProtoArp: Sending reply");
        send_internal(ARP_OPER_REPLY, sha, m_ipaddr, sha, spa);
    } else if (DEBUG_VERBOSE > 1) {
        log::Log(log::DEBUG, "ProtoArp: No reply").write(tpa.value);
    }
}

bool ProtoArp::send_internal(u16 opcode,
    const satcat5::eth::MacAddr& dst,
    const satcat5::ip::Addr& spa,
    const satcat5::eth::MacAddr& tha,
    const satcat5::ip::Addr& tpa) const
{
    // Start with the Ethernet frame header...
    satcat5::io::Writeable* wr =
        m_iface->open_write(dst, eth::ETYPE_ARP);
    if (!wr) return false;          // Unable to proceed?

    // Write packet contents and finalize.
    wr->write_u16(ARP_HTYPE_ETHERNET);
    wr->write_u16(ARP_PTYPE_IPV4);
    wr->write_u8(ARP_HLEN_ETHERNET);
    wr->write_u8(ARP_PLEN_IPV4);
    wr->write_u16(opcode);
    wr->write_obj(m_iface->macaddr()); // SHA = Our MAC-address
    wr->write_obj(spa);             // SPA = Source IP (varies)
    wr->write_obj(tha);             // THA = Target MAC (varies)
    wr->write_obj(tpa);             // TPA = Target IP (varies)
    return wr->write_finalize();    // Send OK?
}
