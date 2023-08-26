//////////////////////////////////////////////////////////////////////////
// Copyright 2022, 2023 The Aerospace Corporation
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
// Automatic "ping" functionality using an ICMP dispatch object
//
// A simplified wrapper for basic "ping" functionality.  Sends ARPING
// (ARP query) or PING (ICMP echo request) messages to the designated
// IP-address once per second.  Results are written to the system Log.
//

#pragma once

#include <satcat5/ip_address.h>
#include <satcat5/ip_icmp.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace ip {
        class Ping final
            : public satcat5::eth::ArpListener
            , public satcat5::ip::PingListener
            , public satcat5::poll::Timer
        {
        public:
            // Tie this Ping wrapper to an IP-dispatch object.
            Ping(satcat5::ip::Dispatch* iface);
            ~Ping() SATCAT5_OPTIONAL_DTOR;

            // All requests can send N queries or until told to stop.
            static constexpr unsigned UNLIMITED = (unsigned)(-1);

            // Begin sending ARPING queries (ARP query).
            void arping(
                const satcat5::ip::Addr& dstaddr,
                unsigned qty = satcat5::ip::Ping::UNLIMITED);

            // Begin sending PING queries (ICMP echo request).
            void ping(
                const satcat5::ip::Addr& dstaddr,
                unsigned qty = satcat5::ip::Ping::UNLIMITED);

            // Stop any ongoing activities.
            void stop();

        private:
            void arp_event(
                const satcat5::eth::MacAddr& mac,
                const satcat5::ip::Addr& ip) override;
            void ping_event(
                const satcat5::ip::Addr& from, u32 elapsed_usec) override;
            void send_arping();
            void send_ping();
            void timer_event() override;

            satcat5::ip::Dispatch* const m_iface;
            satcat5::ip::Address m_addr;
            u32         m_arp_tref;
            unsigned    m_arp_remct;
            unsigned    m_icmp_remct;
            bool        m_reply_rcvd;
        };
    }
}
