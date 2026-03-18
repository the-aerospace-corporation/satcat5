//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_sw_log.h>
#include <satcat5/igmp_client.h>
#include <satcat5/igmp_server.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/utils.h>

using satcat5::igmp::Group;
using satcat5::igmp::Server;
using satcat5::ip::Addr;
using satcat5::ip::ADDR_NONE;
using satcat5::util::countdown;

// Set the polling interval for response timers.
static constexpr unsigned TIMER_INTERVAL_MSEC = 10;

// Internal status flags.
constexpr u8 FLAG_QUERIER = (1u << 0);

void Group::reset(const Addr& addr) {
    group       = addr;
    mask_active = 0;
    mask_rcvd1  = 0;
    mask_rcvd2  = 0;
    query_count = 0;
    query_timer = 0;
}

void Group::rcvd(SATCAT5_PMASK_TYPE mask) {
    satcat5::util::set_mask(mask_active, mask);
    satcat5::util::set_mask(mask_rcvd1, mask);
    satcat5::util::set_mask(mask_rcvd2, mask);
}

void Group::refresh() {
    // End of reporting interval, update membership mask.
    // Merging reports over a few consecutive query/response
    // intervals reduces impact of a single lost packet.
    mask_active = mask_rcvd1 | mask_rcvd2;
    mask_rcvd1 = mask_rcvd2;
    mask_rcvd2 = 0;
    // If there are no members, delete this group.
    if (!mask_active) reset(ADDR_NONE);
}

Server::Server(
    satcat5::eth::SwitchCore* sw,
    satcat5::ip::Dispatch* iface,
    Group* groups, unsigned gcount)
    : PluginCore(sw)
    , m_iface(iface)        // May be null
    , m_groups(groups)
    , m_gcount(gcount)
    , m_status(iface ? FLAG_QUERIER : 0)
    , m_mdly_fast(20)
    , m_mdly_slow(100)
    , m_vmin(3)
    , m_vmax(3)
    , m_query_timer(iface ? 1000 : 0)
    , m_window_timer(0)
{
    timer_every(TIMER_INTERVAL_MSEC);
}

#if SATCAT5_ALLOW_DELETION
Server::~Server() {
    // No additional cleanup required.
}
#endif

void Server::flush() {
    for (u16 a = 0 ; a < m_gcount ; ++a)
        m_groups[a].reset(ADDR_NONE);
    if (m_iface) send_query(nullptr, true);
}

SATCAT5_PMASK_TYPE Server::get_mask(const Addr& addr) const {
    // Special cases for reserved addresses.
    if (addr == DST_ALL_SYSTEMS) return satcat5::eth::PMASK_ALL;
    if (addr == DST_ALL_ROUTERS) return satcat5::eth::PMASK_ALL;

    // Otherwise, search across active groups.
    auto group = find_match(addr);
    return group ? group->mask_active : 0;
}

bool Server::is_querier() const {
    return m_status & FLAG_QUERIER;
}

void Server::query(satcat5::eth::PluginPacket& pkt) {
    if (pkt.is_ip() && pkt.ip.proto() == satcat5::ip::PROTO_IGMP) {
        rcvd_igmp(pkt);     // Process incoming IGMP packet.
    } else if (pkt.is_ip() && pkt.ip.dst().is_multicast()) {
        rcvd_mcast(pkt);    // Route incoming multicast packet.
    }
}

u8 Server::version() const {
    return satcat5::util::min_u8(m_vmin, m_vmax);
}

void Server::timer_event() {
    // Check global timer for the active query/response window.
    // (This may be driven by us, or by another network device.)
    if (countdown<u32>(m_window_timer, TIMER_INTERVAL_MSEC)) {
        for (u16 a = 0 ; a < m_gcount ; ++a)
            m_groups[a].refresh();
    }

    // Separately, check the timer for sending another query.
    // If we are the querier, this is concurrent with end-of-window.
    // If not, this represents a timeout for re-election of a new querier.
    if (countdown<u32>(m_query_timer, TIMER_INTERVAL_MSEC)) {
        if (m_iface) send_query(nullptr, true);
    }

    // Check rapid-refresh timers for specific groups.
    // Rapid request/response up to N times, then stop.
    for (u16 a = 0 ; a < m_gcount ; ++a) {
        if (countdown<u16>(m_groups[a].query_timer, TIMER_INTERVAL_MSEC)) {
            m_groups[a].refresh();
            if (m_iface && ++m_groups[a].query_count < 3) {
                send_query(m_groups + a, false);
            }
        }
    }
}

Group* Server::find_or_create(const Addr& group) {
    bool valid = group.is_multicast() && !group.is_broadcast();
    if (!valid) return nullptr; // Valid multicast address?
    Group* match = find_match(group);
    if (match) return match;    // Found a match
    Group* empty = find_match(ADDR_NONE);
    if (empty) empty->reset(group);
    return empty;               // Create a new entry
}

// Brute-force search over the entire array...
Group* Server::find_match(const Addr& group) const {
    Group* match = nullptr;
    for (u16 a = 0 ; a < m_gcount && !match ; ++a) {
        if (m_groups[a].group == group) match = m_groups + a;
    }
    return match;
}

void Server::rcvd_igmp(satcat5::eth::PluginPacket& pkt) {
    // For routers, this method is called for incoming packets from other
    // devices AND for our own outgoing packets. Forward or drop accordingly.
    if (m_iface) {          // Router mode?
        // Forward self-generated outgoing IGMP packets, but do not process.
        if (pkt.ip.src() == m_iface->ipaddr()) return;
        // Process incoming IGMP packets, but do not forward.
        pkt.dst_mask = 0;
        pkt.flags = satcat5::eth::SwitchLogMessage::DROP_MCTRL;
    }

    // Sanity check incoming packet length.
    unsigned len = pkt.ip.len_inner();
    if (len > MAX_LEN_BYTES || len < MIN_LEN_BYTES) return;
    if (pkt.ip.frg()) return;   // Fragmentation not supported

    // Skip headers and get ready to read message contents.
    // (Note: Ethernet frame may be zero-padded beyond IP end-of-frame.)
    satcat5::io::MultiPacket::Reader raw(pkt.pkt);
    raw.read_consume(pkt.hlen);
    satcat5::io::LimitedRead msg(&raw, len);

    // Validate the IGMP checksum.
    u16 rcvd[MAX_LEN_SHORTS];
    unsigned wcount = 0;
    while (msg.get_read_ready())
        rcvd[wcount++] = msg.read_u16();
    u16 chk = satcat5::ip::checksum(wcount, rcvd);
    if (chk) return;    // Expect total = zero.

    // Decode header fields.
    u16 type = rcvd[0] & MASK_TYPE;
    u16 mdly = rcvd[0] & MASK_MAXLEN;
    Addr addr(rcvd[2], rcvd[3]);

    // Update minimum version for this subnet.
    if (type == TYPE_REPORT_V1 && m_vmin > 1) m_vmin = 1;
    if (type == TYPE_REPORT_V2 && m_vmin > 2) m_vmin = 2;

    // Sort by type header...
    if (type == TYPE_QUERY) {
        // Watch for queries from other routers.  The router with the lowest
        // IP address is elected as the official "querier".  Everybody else
        // should be operating in silent mode, snooping on those queries.
        // TODO: Handling of S-flag, QRV, QQIC, etc...
        if (pkt.ip.src().value < m_iface->ipaddr().value) {
            // Clear the active-querier status flag.
            satcat5::util::clr_mask_u8(m_status, FLAG_QUERIER);
            // Set a watchdog timeout, in case the current querier halts.
            u32 max_dly = decode_maxdly(mdly, wcount > 8);
            if (m_iface) m_query_timer = 2*max_dly;
            m_window_timer = max_dly;
        }
    } else if (type == TYPE_REPORT_V1 || type == TYPE_REPORT_V2) {
        // Membership report for a single address/group.
        auto group = find_or_create(addr);
        if (group) group->rcvd(pkt.src_mask());
    } else if (type == TYPE_REPORT_V3) {
        // Membership report with multiple records...
        unsigned rcount = rcvd[3];
        unsigned rdpos = 4;
        for (unsigned a = 0 ; a < rcount && rdpos + 4 <= wcount ; ++a) {
            // Read each record, ignoring source address filters.
            u16 aux = rcvd[rdpos+0] & MASK_MAXLEN;
            u16 rec = rcvd[rdpos+1];
            Addr dst(rcvd[rdpos+2], rcvd[rdpos+3]);
            rdpos += 4 + 2*aux + 2*rec;
            // Update group membership flags.
            auto group = find_or_create(dst);
            if (group) group->rcvd(pkt.src_mask());
        }
    } else if (type == TYPE_LEAVE_V2 && m_iface) {
        // If any member leaves, immediately refresh that group.
        // (Other endpoints on the same port may still be members.)
        auto group = find_match(addr);
        if (group) send_query(group, true);
    }
}

void Server::rcvd_mcast(satcat5::eth::PluginPacket& pkt) {
    // Leave broadcast packets in broadcast mode.
    Addr dst = pkt.ip.dst();
    if (dst.is_broadcast()) return;

    // Check destination mask based on multicast address.
    pkt.dst_mask &= get_mask(dst);
}

void Server::send_query(Group* group, bool first) {
    // Set MDLY parameter for this query.
    u16 mdly = group ? m_mdly_fast : m_mdly_slow;
    if (version() == 1) mdly = 0;

    // Set the status flag indicating we are the elected querier.
    satcat5::util::set_mask_u8(m_status, FLAG_QUERIER);

    // Window length adds ~25% to catch stragglers.
    u32 msec = (decode_maxdly(mdly, version() == 3) * 5) / 4;

    // Sending this message opens a window for responses.
    // Set a timer to take action at the end of that interval.
    const Addr addr = group ? group->group : ADDR_NONE;
    if (group) {
        // Rapid queries for a specific multicast address.
        if (first) group->query_count = 0;
        group->query_timer = msec;
    } else {
        // Slower pace for general queries.
        m_query_timer  = msec;
        m_window_timer = msec;
    }

    // Write the message header.
    u16 msg[MAX_LEN_SHORTS];
    unsigned wcount = 0;
    msg[wcount++] = TYPE_QUERY | mdly;
    msg[wcount++] = 0; // Placeholder for checksum
    msg[wcount++] = u16(addr.value >> 16);
    msg[wcount++] = u16(addr.value >> 0);
    if (version() == 3) {       // Additional fields for IGMPv3?
        msg[wcount++] = mdly;   // TODO: Handle QQIC correctly.
        msg[wcount++] = 0;      // No source filters
    }
    igmp_send(m_iface, DST_ALL_SYSTEMS, wcount, msg);
}
