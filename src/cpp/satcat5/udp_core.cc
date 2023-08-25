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

#include <satcat5/udp_core.h>
#include <satcat5/udp_dispatch.h>

using satcat5::ip::PROTO_UDP;
using satcat5::udp::Address;

Address::Address(satcat5::udp::Dispatch* iface)
    : m_iface(iface)
    , m_addr(iface->iface(), PROTO_UDP)
    , m_dstport(satcat5::udp::PORT_NONE)
    , m_srcport(satcat5::udp::PORT_NONE)
{
    // No other initialization required.
}

void Address::connect(
    const satcat5::udp::Addr& dstaddr,
    const satcat5::eth::MacAddr& dstmac,
    const satcat5::udp::Port& dstport,
    const satcat5::udp::Port& srcport)
{
    m_dstport = dstport;
    m_srcport = srcport;
    m_addr.connect(dstaddr, dstmac);
}

void Address::connect(
    const satcat5::udp::Addr& dstaddr,
    const satcat5::udp::Port& dstport,
    const satcat5::udp::Port& srcport)
{
    m_dstport = dstport;
    m_srcport = srcport;
    m_addr.connect(dstaddr);
}

satcat5::net::Dispatch* Address::iface() const
{
    return m_iface;
}

satcat5::io::Writeable* Address::open_write(unsigned len)
{
    return m_iface->open_write(m_addr, m_srcport, m_dstport, len);
}
