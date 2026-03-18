//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/igmp_client.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/utils.h>

using satcat5::igmp::Address;
using satcat5::igmp::Client;
using satcat5::ip::Addr;
using satcat5::ip::ADDR_NONE;
using satcat5::util::countdown;
using satcat5::util::min_unsigned;
using satcat5::util::prng;

// Filter "protocol" field for incoming IPv4 packets.
static constexpr satcat5::net::Type
    TYPE_IGMP(satcat5::ip::PROTO_IGMP);

// Set the polling interval for response timers.
static constexpr u32 TIMER_INTERVAL_MSEC = 10;

// Formulate and send an IGMP message.
bool satcat5::igmp::igmp_send(
    satcat5::ip::Dispatch* iface,
    const satcat5::ip::Addr& dst,
    const unsigned wcount, u16* data)
{
    // TODO: Why is this needed? Possible compiler bug?
    //  Adding this line prevents a linker error on Microblaze.
    //  "collect2.exe: error: ld returned 5 exit status"
    if (!SATCAT5_IGMP_ENABLE) return false;

    // Sanity check on array bounds.
    if (wcount < MIN_LEN_SHORTS || !data) return false;

    // In-place calculation of the message checksum.
    // (Same location for all IGMP message types and all versions.)
    data[1] = satcat5::ip::checksum(wcount, data);

    // Write the Ethernet header.
    satcat5::io::Writeable* wr = iface->iface()->open_write(
        satcat5::eth::MACADDR_BROADCAST, satcat5::eth::ETYPE_IPV4);
    if (!wr) return false;

    // Write the IP header with TTL=1 and the "router alert" option.
    satcat5::ip::Header hdr = iface->next_header(
        satcat5::ip::PROTO_IGMP, dst, 2*wcount, 1);
    hdr.option_alert();
    hdr.write_to(wr);

    // Write the message contents.
    for (unsigned a = 0 ; a < wcount ; ++a)
        wr->write_u16(data[a]);
    return wr->write_finalize();
}

u32 satcat5::igmp::decode_maxdly(u16 hdr, bool v3) {
    hdr &= MASK_MAXLEN;
    if (!hdr) return 10000;                 // IGMPv1
    if (hdr < 128 || !v3) return 100*hdr;   // IGMPv2 or IGMPv3-fixed
    u16 mant = (hdr & 0x0F) + 16;
    u16 expn = (hdr & 0x70) >> 4;
    return u32(100 * mant) << (expn + 3);   // IGMPv3-float
}

#if SATCAT5_IGMP_ENABLE

Client::Client(satcat5::ip::Dispatch* iface)
    : Protocol(TYPE_IGMP)   // Accept IGMP packets (proto = 0x02)
    , m_iface(iface)        // Link to parent interface
    , m_reply_timer(0)
    , m_version(3)          // Assume v3, downgrade as needed
{
    m_iface->add(this);
    timer_every(TIMER_INTERVAL_MSEC);
}

Client::~Client() {
    #if SATCAT5_ALLOW_DELETION
    m_iface->remove(this);
    #endif
}

void Client::join(Address& obj, const Addr& addr) {
    // Leave existing group, if we haven't already.
    leave(obj);
    // Sanity check on new group address.
    if (addr.is_broadcast() || !addr.is_multicast()) return;
    // Add the group to the list of active objects.
    obj.m_igmp_group = addr;
    m_groups.add_safe(&obj);
    // Send two "join" messages: one now, one after a short delay.
    if (m_version > 1) {
        send_report(addr);
        obj.m_igmp_timer = prng.next(1, 1000);
    }
}

void Client::leave(Address& obj) {
    // Sanity check on current state.
    if (obj.m_igmp_group == ADDR_NONE) return;
    // If applicable, send a "leave" message.
    if (m_version > 1) send_leave(obj.m_igmp_group);
    // Remove the group from the list of active objects.
    m_groups.remove(&obj);
    obj.m_igmp_group = ADDR_NONE;
}

void Client::frame_rcvd(satcat5::io::LimitedRead& src) {
    // Sanity check the incoming packet length.
    if (src.get_read_ready() > MAX_LEN_BYTES ||
        src.get_read_ready() < MIN_LEN_BYTES) return;

    // Read packet contents and validate the checksum.
    u16 rcvd[MAX_LEN_SHORTS];
    unsigned wcount = 0;
    while (src.get_read_ready())
        rcvd[wcount++] = src.read_u16();
    u16 chk = satcat5::ip::checksum(wcount, rcvd);
    if (chk) return;    // Expect total = zero.

    // Decode header fields.
    u16 type = rcvd[0] & MASK_TYPE;
    u16 mdly = rcvd[0] & MASK_MAXLEN;
    Addr addr(rcvd[2], rcvd[3]);

    // Sort by type header...
    if (type == TYPE_QUERY) {
        // Autodetect the query version (RFC9776, Section 7.1).
        // There should only be one active "Querier" per network.
        if (mdly == 0) {
            m_version = 1;
        } else if (wcount == 4) {
            m_version = 2;
        } else {
            m_version = 3;
        }
        u32 max_dly = decode_maxdly(mdly, wcount > 8);
        // Schedule response(s) with randomized delays.
        if (addr != ADDR_NONE) {
            // Query for a specific address.
            auto match = find_match(addr);
            if (match) set_timer(match->m_igmp_timer, max_dly);
        } else if (m_version == 3) {
            // General query V3: Set timer for all-in-one response.
            set_timer(m_reply_timer, max_dly);
        } else {
            // General query V1 or V2: Set timer for each response.
            Address* item = m_groups.head();
            while (item) {
                set_timer(item->m_igmp_timer, max_dly);
                item = m_groups.next(item);
            }
        }
    } else if (type == TYPE_REPORT_V1 || type == TYPE_REPORT_V2) {
        // Suppress duplicates if we would have responded to the same address.
        // (This behavior was deprecated in IGMPv3, see RFC9776 Appendix A.)
        auto match = find_match(addr);          // GCOVR_EXCL_LINE
        if (match) match->m_igmp_timer = 0;     // GCOVR_EXCL_LINE
    }
}

void Client::timer_event() {
    // Decrement the global countdown timer (IGMPv3 only).
    if (countdown(m_reply_timer, TIMER_INTERVAL_MSEC)) {
        send_report(ADDR_NONE);
    }
    // Decrement each of the per-group timers.
    Address* item = m_groups.head();
    while (item) {
        if (countdown(item->m_igmp_timer, TIMER_INTERVAL_MSEC)) {
            send_report(item->m_igmp_group);
        }
        item = m_groups.next(item);
    }
}

Address* Client::find_match(const Addr& group) const {
    Address* item = m_groups.head();
    while (item && item->m_igmp_group != group) {
        item = m_groups.next(item);
    }
    return item;
}

void Client::send_leave(const Addr& group) {
    u16 msg[MIN_LEN_SHORTS];
    unsigned wcount = 0;
    msg[wcount++] = TYPE_LEAVE_V2;
    msg[wcount++] = 0; // Placeholder for checksum
    msg[wcount++] = u16(group.value >> 16);
    msg[wcount++] = u16(group.value >> 0);
    igmp_send(m_iface, DST_ALL_ROUTERS, wcount, msg);
}

void Client::send_report(const Addr& group) {
    u16 msg[MAX_LEN_SHORTS];
    unsigned wcount = 0;
    if (m_version == 1) {
        // IGMPv1 report with a single address.
        msg[wcount++] = TYPE_REPORT_V1;
        msg[wcount++] = 0;  // Placeholder for checksum
        msg[wcount++] = u16(group.value >> 16);
        msg[wcount++] = u16(group.value >> 0);
        igmp_send(m_iface, group, wcount, msg);
    } else if (m_version == 2) {
        // IGMPv2 report with a single address.
        msg[wcount++] = TYPE_REPORT_V2;
        msg[wcount++] = 0;  // Placeholder for checksum
        msg[wcount++] = u16(group.value >> 16);
        msg[wcount++] = u16(group.value >> 0);
        igmp_send(m_iface, group, wcount, msg);
    } else if (!m_groups.is_empty()) {
        // IGMPv3 report with all desired addresses.
        unsigned len = min_unsigned(MAX_V3_RECORDS, m_groups.len());
        msg[wcount++] = TYPE_REPORT_V3;
        msg[wcount++] = 0;  // Placeholder for checksum
        msg[wcount++] = 0;  // Flags (unused)
        msg[wcount++] = u16(len);
        // Append a record for each group.
        Address* item = m_groups.head();
        for (unsigned a = 0 ; item && a < len ; ++a) {
            msg[wcount++] = RECORD_MODE_EXCL;   // Record type + aux len
            msg[wcount++] = 0;                  // No source-address filters
            msg[wcount++] = u16(item->m_igmp_group.value >> 16);
            msg[wcount++] = u16(item->m_igmp_group.value >> 0);
            item = m_groups.next(item);         // Traverse linked list
        }
        igmp_send(m_iface, DST_IGMPV3_REPORT, wcount, msg);
    }
}

void Client::set_timer(u32& timer, u32 max_msec) {
    // Randomize the delay amount, then keep the shortest of new and old.
    u32 new_dly = prng.next(1, max_msec);
    if (new_dly < timer || !timer) timer = new_dly;
}

#else   // SATCAT5_IGMP_ENABLE

// If IGMP is disabled, provide empty stubs for all public methods.
Client::Client(satcat5::ip::Dispatch* iface) {}
Client::~Client() {}
void Client::join(Address& obj, const Addr& addr) {}
void Client::leave(Address& obj) {}

#endif  // SATCAT5_IGMP_ENABLE
