//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_dispatch.h>
#include <satcat5/router2_deferfwd.h>
#include <satcat5/router2_dispatch.h>

using satcat5::eth::MacAddr;
using satcat5::router2::DeferFwd;
using satcat5::router2::DeferPkt;
using satcat5::router2::Dispatch;
using satcat5::eth::SwitchPlugin;

// Set verbosity level for debugging (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

// Set default retry parameters:
#ifndef SATCAT5_R2_RETRY_MAX    // Maximum number of retries
#define SATCAT5_R2_RETRY_MAX    4
#endif

#ifndef SATCAT5_R2_RETRY_MSEC   // Timeout for the first retry
#define SATCAT5_R2_RETRY_MSEC   10
#endif

bool DeferPkt::read_meta(satcat5::eth::SwitchPlugin::PacketMeta& meta) {
    // Read the Ethernet and IPv4 headers.
    bool ok = meta.read_from(pkt);  // Read packet headers
    meta.dst_mask = dst_mask;       // Restore the destination mask
    return ok;
}

DeferFwd::DeferFwd(Dispatch* parent, DeferPkt* buff, unsigned bcount)
    : m_parent(parent)
    , m_arp(0)
    , m_tref(SATCAT5_CLOCK->now())
    , m_active()
    , m_empty()
{
    // Initialize the list of empty slots.
    for (unsigned a = 0 ; a < bcount ; ++a) {
        m_empty.add(buff + a);
    }

    // Start the timer.
    timer_every(3);
}

#if SATCAT5_ALLOW_DELETION
DeferFwd::~DeferFwd() {
    // Unregister ARP handler if applicable.
    if (m_arp) m_arp->remove(this);
}
#endif

bool DeferFwd::accept(const satcat5::eth::SwitchPlugin::PacketMeta& meta) {
    // First-time setup of the interface? Register for ARP callbacks.
    // (This information may not be available during object creation.)
    if (!m_parent->iface()) return false;
    if (!m_arp) {
        m_arp = m_parent->iface()->arp();
        m_arp->add(this);
        m_tref = SATCAT5_CLOCK->now();
    }

    // Is there an empty slot ready?
    DeferPkt* next = m_empty.pop_front();
    if (next) {
        // Store the new packet on the active list.
        next->pkt       = meta.pkt;
        next->dst_ip    = meta.ip.dst();
        next->dst_mask  = meta.dst_mask;
        next->sent      = 0;
        next->trem      = 0;
        m_active.add(next);
        // Attempt to send the first ARP request.
        request_arp(next);
    }
    return !!next;
}

void DeferFwd::arp_event(const MacAddr& mac, const satcat5::ip::Addr& ip) {
    // Check the incoming MAC/IP pair against each pending packet.
    // If we find a match, pass it back to the router for delivery.
    DeferPkt* pkt = m_active.head();
    while (pkt) {
        pkt = (pkt->dst_ip == ip) ? request_fwd(pkt, mac) : m_active.next(pkt);
    }
}

void DeferFwd::timer_event() {
    // Sanity check that the parent has been fully configured.
    if (!m_arp) return;

    // Elapsed time since last timer_event().
    u32 elapsed = m_tref.increment_msec();

    // Decrement remaining time on each queued packet.
    // When it reaches zero, send another ARP request or discard the packet.
    DeferPkt* pkt = m_active.head();
    while (pkt) {
        if (pkt->trem < elapsed) {
            pkt = request_arp(pkt);
        } else {
            pkt->trem -= elapsed;
            pkt = m_active.next(pkt);
        }
    }
}

DeferPkt* DeferFwd::request_arp(DeferPkt* pkt) {
    // Note the "next" pointer before we mutate the list.
    DeferPkt* next = m_active.next(pkt);

    // Check the number of previous attempts...
    if (pkt->sent <= SATCAT5_R2_RETRY_MAX) {
        // Exponential backoff when setting the next timeout.
        pkt->trem = u16(SATCAT5_R2_RETRY_MSEC) << (pkt->sent++);
        // Attempt to send the next ARP request.
        // (OK if this fails, timeout is the same either way.)
        m_arp->send_query(pkt->dst_ip);
    } else {
        // Retry limit exceeded, send an ICMP error.
        SwitchPlugin::PacketMeta meta;
        if (pkt->read_meta(meta))
            m_parent->icmp_reply(satcat5::ip::ICMP_UNREACHABLE_HOST, 0, meta);
        // Discard the original packet and mark it as empty.
        m_parent->free_packet(pkt->pkt);
        m_active.remove(pkt);
        m_empty.add(pkt);
    }

    // Return the next item for continued processing.
    return next;
}

DeferPkt* DeferFwd::request_fwd(DeferPkt* pkt, const MacAddr& dst) {
    // Note the "next" pointer before we mutate the list.
    DeferPkt* next = m_active.next(pkt);

    // Reconstitute the packet and forward to the designated MAC address.
    // (This packet has already been validated and had its TTL decremented.)
    unsigned count = 0;
    SwitchPlugin::PacketMeta meta;
    if (pkt->read_meta(meta)) {
        m_parent->adjust_mac(dst, meta);
        auto debug = m_parent->m_debug;
        if (DEBUG_VERBOSE > 0 && debug) meta.pkt->copy_to(debug);
        count = m_parent->deliver_offload(meta)
              + m_parent->deliver_switch(meta);
    }

    // If delivery failed, delete the packet buffer.
    if (count == 0) m_parent->free_packet(pkt->pkt);

    // In all cases, mark the queue slot as empty.
    m_active.remove(pkt);
    m_empty.add(pkt);

    // Return the next item for continued processing.
    return next;
}
