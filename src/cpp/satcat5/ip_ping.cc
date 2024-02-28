//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_ping.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/log.h>
#include <satcat5/timer.h>

using satcat5::ip::Ping;
namespace log = satcat5::log;

Ping::Ping(satcat5::ip::Dispatch* iface)
    : m_iface(iface)
    , m_addr(iface, satcat5::ip::PROTO_ICMP)
    , m_arp_tref(0)
    , m_arp_remct(0)
    , m_icmp_remct(0)
    , m_reply_rcvd(false)
{
    // No other initialization required.
}

#if SATCAT5_ALLOW_DELETION
Ping::~Ping()
{
    stop();
}
#endif

void Ping::arping(
    const satcat5::ip::Addr& dstaddr,
    unsigned qty)
{
    stop();                         // Reset internal state.
    if (qty > 0) {
        // Set initial state for ARP-ping.
        m_addr.connect(dstaddr, satcat5::eth::MACADDR_NONE);
        m_arp_remct = qty;          // How many ARP queries?
        m_icmp_remct = 0;           // No ICMP queries
        timer_every(1000);          // Timer for follow-up
        m_iface->m_arp.add(this);   // Register for callback
        // Send the first ARP query.
        send_arping();
    }
}

void Ping::ping(
    const satcat5::ip::Addr& dstaddr,
    unsigned qty)
{
    stop();                         // Reset internal state.
    if (qty > 0) {
        // Set initial state for ICMP-ping.
        m_arp_remct = 2;            // Additional ARP attempts?
        m_icmp_remct = qty;         // How many ICMP queries?
        timer_every(1000);          // Timer for follow-up
        m_iface->m_icmp.add(this);  // Register for callback
        // Start address resolution.
        m_addr.connect(dstaddr);
    }
}

void Ping::stop()
{
    // Reset internal state.
    m_arp_remct = 0;
    m_icmp_remct = 0;
    timer_stop();
    // Unregister callbacks (safe to remove even if not on list.)
    m_iface->m_arp.remove(this);
    m_iface->m_icmp.remove(this);
}

void Ping::arp_event(
    const satcat5::eth::MacAddr& mac,
    const satcat5::ip::Addr& ip)
{
    if (ip == m_addr.dstaddr()) {
        m_reply_rcvd = true;
        u32 elapsed_usec = m_iface->m_timer->elapsed_usec(m_arp_tref);
        log::Log(log::INFO, "Ping: Reply from").write(ip)
            .write(", elapsed usec").write10(elapsed_usec);
    }
}

void Ping::ping_event(const satcat5::ip::Addr& from, u32 elapsed_usec)
{
    if (from == m_addr.dstaddr()) {
        m_reply_rcvd = true;
        log::Log(log::INFO, "Ping: Reply from").write(from)
            .write(", elapsed usec").write10(elapsed_usec);
    }
}

void Ping::send_arping()
{
    // Send an ARP query to the stored address.
    m_reply_rcvd = false;
    m_arp_tref = m_iface->m_timer->now();
    m_iface->m_arp.send_query(m_addr.dstaddr());

    // Decrement counter (unless unlimited).
    if (m_arp_remct != Ping::UNLIMITED) {--m_arp_remct;}
}

void Ping::send_ping()
{
    if (m_addr.ready()) {
        // Send an ICMP query to the resolved address.
        m_reply_rcvd = false;
        m_iface->m_icmp.send_ping(m_addr);
        // Decrement counter (unless unlimited).
        m_arp_remct = 0;
        if (m_icmp_remct != Ping::UNLIMITED) {--m_icmp_remct;}
    } else if (m_arp_remct > 0) {
        // Re-attempt address resolution.
        --m_arp_remct;
        m_addr.retry();
    } else {
        // No ARP response after several attempts.
        log::Log(log::INFO, "Ping: Gateway unreachable").write(m_addr.gateway());
        stop();
    }
}

void Ping::timer_event()
{
    if (m_icmp_remct && m_arp_remct && m_addr.ready()) {
        // No message after a successful ARP handshake.
    } else if (!m_reply_rcvd) {
        log::Log(log::INFO, "Ping: Request timed out.");
    }

    if (m_icmp_remct) {
        send_ping();
    } else if (m_arp_remct) {
        send_arping();
    } else {
        stop();
    }
}
