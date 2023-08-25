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

#include <satcat5/udp_socket.h>

using satcat5::net::Type;
using satcat5::udp::SocketCore;

satcat5::udp::Socket::Socket(satcat5::udp::Dispatch* iface)
    : SocketCore(iface,
        m_txbuff, SATCAT5_UDP_BUFFSIZE, SATCAT5_UDP_PACKETS,
        m_rxbuff, SATCAT5_UDP_BUFFSIZE, SATCAT5_UDP_PACKETS)
{
    // No other initialization required.
}

SocketCore::SocketCore(
        satcat5::udp::Dispatch* iface,
        u8* txbuff, unsigned txbytes, unsigned txpkt,
        u8* rxbuff, unsigned rxbytes, unsigned rxpkt)
    : satcat5::udp::AddressContainer(iface)
    , satcat5::net::SocketCore(&m_addr,
        txbuff, txbytes, txpkt,
        rxbuff, rxbytes, rxpkt)
{
    // No other initialization required.
}

void SocketCore::bind(const satcat5::udp::Port& port)
{
    m_addr.close();                     // Unbind Tx
    m_filter = Type(port.value);        // Rebind Rx
}

void SocketCore::connect(
    const satcat5::udp::Addr& dstaddr,
    const satcat5::eth::MacAddr& dstmac,
    const satcat5::udp::Port& dstport,
    satcat5::udp::Port srcport)
{
    if (srcport == satcat5::udp::PORT_NONE)
        srcport = m_addr.m_iface->next_free_port();
    m_addr.connect(dstaddr, dstmac, dstport, srcport);
    m_filter = Type(srcport.value);     // Rebind Rx
}

void SocketCore::connect(
    const satcat5::udp::Addr& dstaddr,
    const satcat5::udp::Port& dstport,
    satcat5::udp::Port srcport)
{
    if (srcport == satcat5::udp::PORT_NONE)
        srcport = m_addr.m_iface->next_free_port();
    m_addr.connect(dstaddr, dstport, srcport);
    m_filter = Type(srcport.value);     // Rebind Rx
}
