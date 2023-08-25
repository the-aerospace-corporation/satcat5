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
// Protocol handler for the Address Resolution Protocol (ARP)
//
// ARP is the protocol used to find the Ethernet MAC-address that corresponds
// to a particular LAN IP-address.  This file defines a protocol handler for
// sending and receiving ARP messages, as well as hooks for other classes
// to respond to those messages.

#pragma once

#include <satcat5/ethernet.h>
#include <satcat5/ip_core.h>
#include <satcat5/list.h>

namespace satcat5 {
    namespace eth {
        // Callback interface for responding to ARP and ICMP events.
        class ArpListener {
        public:
            // Callback for any announced MAC/IP address pair.
            // Child class MUST override this method.
            virtual void arp_event(
                const satcat5::eth::MacAddr& mac,
                const satcat5::ip::Addr& ip) = 0;

            // Callback for changes to gateway configuration.
            // Child class MAY override this method.
            virtual void gateway_change(
                const satcat5::ip::Addr& dstaddr,
                const satcat5::ip::Addr& gateway) {}

        private:
            // Linked list to the next listener object.
            friend satcat5::util::ListCore;
            satcat5::eth::ArpListener* m_next;
        };

        // Protocol handler for Ethernet-to-IPv4 ARP queries and replies.
        class ProtoArp : public satcat5::eth::Protocol {
        public:
            ProtoArp(
                satcat5::eth::Dispatch* dispatcher,
                const satcat5::ip::Addr& ipaddr = satcat5::ip::ADDR_NONE);

            // Register or unregister event-listeners.
            inline void add(satcat5::eth::ArpListener* evt)
                {m_listeners.add(evt);}
            inline void remove(satcat5::eth::ArpListener* evt)
                {m_listeners.remove(evt);}

            // Set the local IP address.
            inline void set_ipaddr(const satcat5::ip::Addr& ipaddr)
                {m_ipaddr = ipaddr;}

            // Send an unsolicited ARP announcement.
            bool send_announce() const;

            // Send a probe to test if a given address is occupied.
            bool send_probe(const satcat5::ip::Addr& target);

            // Send a query for a given IP address.
            bool send_query(const satcat5::ip::Addr& target);

            // Notify all listeners of a change in gateway configuration.
            void gateway_change(
                const satcat5::ip::Addr& dstaddr,
                const satcat5::ip::Addr& gateway);

        protected:
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            bool send_internal(u16 opcode,
                const satcat5::eth::MacAddr& dst,
                const satcat5::ip::Addr& spa,
                const satcat5::eth::MacAddr& tha,
                const satcat5::ip::Addr& tpa) const;

            satcat5::ip::Addr m_ipaddr;
            satcat5::util::List<satcat5::eth::ArpListener> m_listeners;
        };
    }
}
