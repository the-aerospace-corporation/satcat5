//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_address.h>
#include <satcat5/eth_dispatch.h>

using satcat5::eth::Address;

Address::Address(satcat5::eth::Dispatch* iface)
    : m_iface(iface)
    , m_addr(satcat5::eth::MACADDR_NONE)
    , m_type(satcat5::eth::ETYPE_NONE)
    , m_vtag(satcat5::eth::VTAG_NONE)
{
    // Nothing else to initialize.
}

void Address::connect(
    const satcat5::eth::MacAddr& addr,
    const satcat5::eth::MacType& type,
    const satcat5::eth::VlanTag& vtag)
{
    m_addr = addr;
    m_type = type;
    m_vtag = vtag;
}

satcat5::net::Dispatch* Address::iface() const {
    return m_iface;
}

satcat5::io::Writeable* Address::open_write(unsigned len) {
    return m_iface->open_write(m_addr, m_type, m_vtag);
}

void Address::close() {
    m_addr = satcat5::eth::MACADDR_NONE;
    m_type = satcat5::eth::ETYPE_NONE;
    m_vtag = satcat5::eth::VTAG_NONE;
}

bool Address::ready() const {
    return !(m_addr == satcat5::eth::MACADDR_NONE)
        && !(m_type == satcat5::eth::ETYPE_NONE);
}

bool Address::is_multicast() const {
    return m_addr.is_multicast();
}

bool Address::matches_reply_address() const {
    bool dst_match = m_addr.is_multicast() || m_addr == m_iface->reply_mac();
    bool vid_match = m_iface->reply_vtag().vid() == m_vtag.vid();
    return dst_match && vid_match;
}

bool Address::reply_is_multicast() const {
    return m_iface->reply_is_multicast();
}

void Address::save_reply_address() {
    m_addr = m_iface->reply_mac();
    m_type = m_iface->reply_type();
    m_vtag = m_iface->reply_vtag();
}

