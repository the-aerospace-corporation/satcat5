//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2023 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
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
