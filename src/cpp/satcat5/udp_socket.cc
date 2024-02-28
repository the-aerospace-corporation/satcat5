//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
