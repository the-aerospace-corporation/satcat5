//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_socket.h>

using satcat5::net::Type;
using satcat5::eth::SocketCore;

satcat5::eth::Socket::Socket(satcat5::eth::Dispatch* iface)
    : SocketCore(iface,
        m_txbuff, SATCAT5_ESOCK_BUFFSIZE, SATCAT5_ESOCK_PACKETS,
        m_rxbuff, SATCAT5_ESOCK_BUFFSIZE, SATCAT5_ESOCK_PACKETS)
{
    // No other initialization required.
}

SocketCore::SocketCore(
        satcat5::eth::Dispatch* iface,
        u8* txbuff, unsigned txbytes, unsigned txpkt,
        u8* rxbuff, unsigned rxbytes, unsigned rxpkt)
    : satcat5::eth::AddressContainer(iface)
    , satcat5::net::SocketCore(&m_addr,
        txbuff, txbytes, txpkt,
        rxbuff, rxbytes, rxpkt)
{
    // No other initialization required.
}

void SocketCore::bind(
    const satcat5::eth::MacType& lcltype,
    const satcat5::eth::VlanTag& vtag)
{
    m_addr.close();                                 // Unbind Tx
    m_filter = Type(vtag.vid(), lcltype.value);     // Rebind Rx
}

void SocketCore::connect(
    const satcat5::eth::MacAddr& dstmac,
    const satcat5::eth::MacType& dsttype,
    const satcat5::eth::MacType& lcltype,
    const satcat5::eth::VlanTag& vtag)
{
    m_addr.connect(dstmac, dsttype);                // Rebind Tx
    m_filter = Type(vtag.vid(), lcltype.value);     // Rebind Rx
}
