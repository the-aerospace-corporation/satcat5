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
// All-in-one Internet Protocol stack with all basic services.
//
// This file defines an all-in-one wrapper that makes it easier to use the
// SatCat5 IPv4 protocol stack.  Users can instantiate these objects
// directly for a slimmer design, but this class provides more accessible
// basket of commonly-used services.  The only prerequisites are an Ethernet
// connection (e.g., port::MailMap) and a time reference (e.g., cfg::Timer).
//
// The wrapper includes all of the basic IPv4 services:
//  * Address Resolution Protocol (ARP)
//  * Internet Control Message Protocol (ICMP)
//  * User Datagraph Protocol (UDP)
//  * User-facing services including Ping and UDP-echo.
//

#pragma once

#include <satcat5/eth_chat.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/ip_ping.h>
#include <satcat5/net_echo.h>
#include <satcat5/udp_dispatch.h>

namespace satcat5 {
    namespace ip {
        class Stack {
        public:
            Stack(
                const satcat5::eth::MacAddr& local_mac, // Local MAC address
                const satcat5::ip::Addr& local_ip,      // Local IP address
                satcat5::io::Writeable* dst,            // Ethernet port (Tx)
                satcat5::io::Readable* src,             // Ethernet port (Rx)
                satcat5::util::GenericTimer* timer);    // Time reference

            // Core protocol stack.
            satcat5::eth::Dispatch      m_eth;          // Ethernet layer
            satcat5::ip::Dispatch       m_ip;           // IPv4 and ICMP layer
            satcat5::udp::Dispatch      m_udp;          // UDP layer

            // User services.
            satcat5::udp::ProtoEcho     m_echo;         // Echo on UDP port 7
            satcat5::ip::Ping           m_ping;         // Ping+Arping utilities

            // Other accessors:
            inline satcat5::ip::Addr ipaddr() const
                {return m_ip.ipaddr();}
            inline satcat5::eth::MacAddr macaddr() const
                {return m_ip.macaddr();}
            inline void set_addr(const satcat5::ip::Addr& addr)
                {m_ip.set_addr(addr);}
        };
    }
}
