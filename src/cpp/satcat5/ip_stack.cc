//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_stack.h>

using satcat5::ip::Stack;

Stack::Stack(
        const satcat5::eth::MacAddr& local_mac, // Local MAC address
        const satcat5::ip::Addr& local_ip,      // Local IP address
        satcat5::io::Writeable* dst,            // Ethernet port (Tx)
        satcat5::io::Readable* src,             // Ethernet port (Rx)
        satcat5::util::GenericTimer* timer)     // Time reference
    : m_eth(local_mac, dst, src, timer)
    , m_ip(local_ip, &m_eth, timer)
    , m_udp(&m_ip)
    , m_echo(&m_udp)
    , m_ping(&m_ip)
{
    // No other initialization required
}
