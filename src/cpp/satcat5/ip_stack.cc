//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation
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

#include <satcat5/ip_stack.h>

using satcat5::ip::Stack;

Stack::Stack(
        const satcat5::eth::MacAddr& local_mac, // Local MAC address
        const satcat5::ip::Addr& local_ip,      // Local IP address
        satcat5::io::Writeable* dst,            // Ethernet port (Tx)
        satcat5::io::Readable* src,             // Ethernet port (Rx)
        satcat5::util::GenericTimer* timer)     // Time reference
    : m_eth(local_mac, dst, src)
    , m_ip(local_ip, &m_eth, timer)
    , m_udp(&m_ip)
    , m_echo(&m_udp)
    , m_ping(&m_ip)
{
    // No other initialization required
}
