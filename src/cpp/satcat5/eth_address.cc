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

#if SATCAT5_VLAN_ENABLE
void Address::connect(
    const satcat5::eth::MacAddr& addr,
    const satcat5::eth::MacType& type,
    const satcat5::eth::VlanTag& vtag)
{
    m_addr = addr;
    m_type = type;
    m_vtag = vtag;
}
#else
void Address::connect(
    const satcat5::eth::MacAddr& addr,
    const satcat5::eth::MacType& type)
{
    m_addr = addr;
    m_type = type;
}
#endif

satcat5::net::Dispatch* Address::iface() const
{
    return m_iface;
}

satcat5::io::Writeable* Address::open_write(unsigned len)
{
    #if SATCAT5_VLAN_ENABLE
    return m_iface->open_write(m_addr, m_type, m_vtag);
    #else
    return m_iface->open_write(m_addr, m_type);
    #endif
}

void Address::close()
{
    m_addr = satcat5::eth::MACADDR_NONE;
    m_type = satcat5::eth::ETYPE_NONE;
    #if SATCAT5_VLAN_ENABLE
    m_vtag = satcat5::eth::VTAG_NONE;
    #endif
}

bool Address::ready() const
{
    return !(m_addr == satcat5::eth::MACADDR_NONE)
        && !(m_type == satcat5::eth::ETYPE_NONE);
}
