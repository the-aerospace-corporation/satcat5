//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/udp_dispatch.h>
#include <satcat5/udp_keep_alive.h>

using satcat5::udp::KeepAlive;

KeepAlive::KeepAlive(
    satcat5::udp::Dispatch* iface,
    satcat5::udp::Port port,
    const char* label)
    : Protocol(satcat5::net::Type(port.value))
    , m_addr(iface)
    , m_label(label)
{
    m_addr.iface()->add(this);
    m_addr.connect(satcat5::ip::ADDR_BROADCAST, port, port);
}

KeepAlive::~KeepAlive() {
    m_addr.iface()->remove(this);
}

void KeepAlive::connect(
    const satcat5::ip::Addr& dstaddr,
    const satcat5::eth::VlanTag& vtag)
{
    auto dstport = m_addr.dstport();
    m_addr.connect(dstaddr, dstport, dstport, vtag);
}

void KeepAlive::send_now(const char* msg) {
    unsigned len = msg ? strlen(msg) : 0;
    auto wr = m_addr.open_write(len);
    if (wr) {
        if (msg) wr->write_str(msg);
        wr->write_finalize();
    }
}

void KeepAlive::frame_rcvd(satcat5::io::LimitedRead& src) {
    // Discard all incoming packets with no further action.
}

void KeepAlive::timer_event() {
    send_now(m_label);
}
