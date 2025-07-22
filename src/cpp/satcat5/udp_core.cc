//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/udp_core.h>
#include <satcat5/udp_dispatch.h>

using satcat5::ip::PROTO_UDP;
using satcat5::udp::Address;
using satcat5::udp::PORT_NONE;

Address::Address(satcat5::udp::Dispatch* iface)
    : m_iface(nullptr)
    , m_addr(nullptr, PROTO_UDP)
    , m_dstport(PORT_NONE)
    , m_srcport(PORT_NONE)
{
    init(iface);
}

void Address::init(satcat5::udp::Dispatch* iface) {
    if (iface && !m_iface) {
        m_iface = iface;
        m_addr.init(iface->iface());
    }
}

void Address::connect(
    const satcat5::udp::Addr& dstaddr,
    const satcat5::eth::MacAddr& dstmac,
    const satcat5::udp::Port& dstport,
    const satcat5::udp::Port& srcport,
    const satcat5::eth::VlanTag& vtag)
{
    m_dstport = dstport;
    m_srcport = (m_iface && srcport == PORT_NONE)
        ? m_iface->next_free_port() : srcport;
    m_addr.connect(dstaddr, dstmac, vtag);
}

void Address::connect(
    const satcat5::udp::Addr& dstaddr,
    const satcat5::udp::Port& dstport,
    const satcat5::udp::Port& srcport,
    const satcat5::eth::VlanTag& vtag)
{
    m_dstport = dstport;
    m_srcport = (m_iface && srcport == PORT_NONE)
        ? m_iface->next_free_port() : srcport;
    m_addr.connect(dstaddr, vtag);
}

bool Address::matches_reply_address() const {
    return m_iface
        && m_addr.matches_reply_address()
        && m_iface->reply_src() == dstport()
        && m_iface->reply_dst() == srcport();
}

satcat5::net::Dispatch* Address::iface() const {
    return m_iface;
}

satcat5::io::Writeable* Address::open_write(unsigned len) {
    return m_iface ? m_iface->open_write(m_addr, m_srcport, m_dstport, len) : nullptr;
}

void Address::save_reply_address() {
    if (m_iface) {
        m_addr.save_reply_address();        // Save IP/MAC/VLAN parameters
        m_dstport = m_iface->reply_src();   // Swap dst/src port numbers
        m_srcport = m_iface->reply_dst();
    }
}

void satcat5::udp::Header::write_to(satcat5::io::Writeable* wr) const {
    src.write_to(wr);
    dst.write_to(wr);
    wr->write_u16(length);
    // Checksum of 0 means checksum is disabled as permitted under IETF RFC 768
    wr->write_u16(0x0);
}

bool satcat5::udp::Header::read_from(satcat5::io::Readable* rd) {
    if (rd->get_read_ready() < 8) {return false;}
    src.read_from(rd);
    dst.read_from(rd);
    length = rd->read_u16();
    // Read and discard checksum
    rd->read_u16();
    return true;
}
