//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_dispatch.h>
#include <satcat5/eth_protocol.h>

using satcat5::eth::Address;
using satcat5::eth::Dispatch;
using satcat5::eth::MacType;
using satcat5::eth::VlanTag;
using satcat5::net::Type;

satcat5::eth::Protocol::Protocol(
        Dispatch* dispatch,
        const MacType& ethertype)
    : satcat5::net::Protocol(Type(ethertype.value))
    , m_iface(dispatch)
    , m_etype(ethertype)
{
    m_iface->add(this);
}

#if SATCAT5_VLAN_ENABLE
satcat5::eth::Protocol::Protocol(
        Dispatch* dispatch,
        const MacType& ethertype,
        const VlanTag& vtag)
    : satcat5::net::Protocol(Type(vtag.vid(), ethertype.value))
    , m_iface(dispatch)
    , m_etype(ethertype)
{
    m_iface->add(this);
}
#endif

#if SATCAT5_ALLOW_DELETION
satcat5::eth::Protocol::~Protocol()
{
    m_iface->remove(this);
}
#endif
