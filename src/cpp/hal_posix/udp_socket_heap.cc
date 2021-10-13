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
