//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_posix/udp_socket_heap.h>

using satcat5::udp::SocketCore;
using satcat5::udp::SocketHeap;

SocketHeap::SocketHeap(
        satcat5::udp::Dispatch* iface,
        unsigned txbytes, unsigned rxbytes)
    : SocketCore(iface,
        new u8[txbytes], txbytes, txbytes/64,
        new u8[rxbytes], rxbytes, rxbytes/64)
{
    // No other initialization required.
}

SocketHeap::~SocketHeap()
{
    delete[] m_tx.get_buff_dtor();
    delete[] m_rx.get_buff_dtor();
}
