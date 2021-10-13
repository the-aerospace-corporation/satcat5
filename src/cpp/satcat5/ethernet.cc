//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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

#include <satcat5/ethernet.h>
#include <satcat5/eth_dispatch.h>

using satcat5::eth::Address;
using satcat5::eth::Header;
using satcat5::eth::MacAddr;

bool MacAddr::operator==(const eth::MacAddr& other) const {
    return (addr[0] == other.addr[0])
        && (addr[1] == other.addr[1])
        && (addr[2] == other.addr[2])
        && (addr[3] == other.addr[3])
        && (addr[4] == other.addr[4])
        && (addr[5] == other.addr[5]);
}

bool MacAddr::operator<(const eth::MacAddr& other) const {
    for (unsigned a = 0 ; a < 6 ; ++a) {
        if (addr[a] < other.addr[a]) return true;
        if (addr[a] > other.addr[a]) return false;
    }
    return false;   // All bytes equal
}

void Header::write_to(io::Writeable* wr) const
{
    dst.write_to(wr);
    src.write_to(wr);
    type.write_to(wr);
}

bool Header::read_from(io::Readable* rd)
{
    if (rd->get_read_ready() < 14) {
        return false;   // Error
    } else {
        dst.read_from(rd);
        src.read_from(rd);
        type.read_from(rd);
        return true;    // Success
    }
}

Address::Address(satcat5::eth::Dispatch* iface)
    : m_iface(iface)
    , m_addr(satcat5::eth::MACADDR_NONE)
    , m_type(satcat5::eth::ETYPE_NONE)
{
    // Nothing else to initialize.
}

void Address::connect(
    const satcat5::eth::MacAddr& addr,
    const satcat5::eth::MacType& type)
{
    m_addr = addr;
    m_type = type;
}

satcat5::net::Dispatch* Address::iface() const
{
    return m_iface;
}

satcat5::io::Writeable* Address::open_write(unsigned len) const
{
    return m_iface->open_write(m_addr, m_type);
}

void Address::close()
{
    m_addr = satcat5::eth::MACADDR_NONE;
    m_type = satcat5::eth::ETYPE_NONE;
}

bool Address::ready() const
{
    return !(m_addr == satcat5::eth::MACADDR_NONE)
        && !(m_type == satcat5::eth::ETYPE_NONE);
}

satcat5::eth::Protocol::Protocol(
        eth::Dispatch* dispatch,
        const eth::MacType& ethertype)
    : satcat5::net::Protocol(satcat5::net::Type(ethertype.value))
    , m_iface(dispatch)
    , m_etype(ethertype)
{
    m_iface->add(this);
}

#if SATCAT5_ALLOW_DELETION
satcat5::eth::Protocol::~Protocol()
{
    m_iface->remove(this);
}
#endif
