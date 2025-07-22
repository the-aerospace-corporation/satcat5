//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Protocol handler for the Address Resolution Protocol (ARP)
//!
//!\details
//! ARP is the protocol used to find the Ethernet MAC-address that corresponds
//! to a particular LAN IP-address.  This file defines a protocol handler for
//! sending and receiving ARP messages, as well as hooks for other classes
//! to respond to those messages.

#pragma once

#include <satcat5/ethernet.h>
#include <satcat5/ip_core.h>
#include <satcat5/list.h>

namespace satcat5 {
    namespace eth {
        //! Address Resolution Protocol header. \see eth_arp.h.
        struct ArpHeader {
            //! ARP header fields:
            //!@{
            u16 oper;                           // Operation (1 = request, 2 = reply)
            satcat5::eth::MacAddr   sha, tha;   // MAC ("hardware address")
            satcat5::ip::Addr       spa, tpa;   // IPv4 ("protocol address")
            //!@}

            //! Constructor for an empty header.
            constexpr ArpHeader()
                : oper(0), sha{}, tha{}, spa(), tpa() {}

            //! Attempt to read and validate the header.
            bool read_from(satcat5::io::Readable* rd);

            //! Write header contents to the specified destination.
            void write_to(satcat5::io::Writeable* wr) const;
        };

        //! Callback interface for responding to ARP and ICMP events.
        //! \see eth_arp.h, eth::ProtoArp.
        class ArpListener {
        public:
            //! Callback for any announced MAC/IP address pair.
            //! Child class MUST override this method.
            virtual void arp_event(
                const satcat5::eth::MacAddr& mac,
                const satcat5::ip::Addr& ip) = 0;

            //! Callback for changes to gateway configuration.
            //! Child class MAY override this method.
            virtual void gateway_change(
                const satcat5::ip::Addr& dstaddr,
                const satcat5::ip::Addr& gateway) {}

        private:
            // Linked list to the next listener object.
            friend satcat5::util::ListCore;
            satcat5::eth::ArpListener* m_next;
        };

        //! Protocol handler for Ethernet-to-IPv4 ARP queries and replies.
        //! \see eth_arp.h, eth::ArpListener.
        class ProtoArp : public satcat5::eth::Protocol {
        public:
            //! Attach this ARP handler to an eth::Dispatch interface.
            ProtoArp(
                satcat5::eth::Dispatch* dispatcher,
                const satcat5::ip::Addr& ipaddr = satcat5::ip::ADDR_NONE);

            //! Register an event-listener.
            inline void add(satcat5::eth::ArpListener* evt)
                {m_listeners.add(evt);}
            //! Unregister an event-listener.
            inline void remove(satcat5::eth::ArpListener* evt)
                {m_listeners.remove(evt);}

            //! Set the local IP address.
            inline void set_ipaddr(const satcat5::ip::Addr& ipaddr)
                {m_ipaddr = ipaddr;}

            //! Set IP routing table to enable proxy-ARP.
            inline void set_proxy(const satcat5::ip::Table* table)
                {m_table = table;}

            //! Send an unsolicited ARP announcement.
            bool send_announce(
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE) const;

            //! Send a probe to test if a given address is occupied.
            bool send_probe(
                const satcat5::ip::Addr& target,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            //! Send a query for a given IP address.
            bool send_query(
                const satcat5::ip::Addr& target,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            //! Notify all listeners of a change in gateway configuration.
            void gateway_change(
                const satcat5::ip::Addr& dstaddr,
                const satcat5::ip::Addr& gateway);

            //! New-frame notifications from the parent interface.
            //! (This may be called directly or through eth::Dispatch.)
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

        protected:
            satcat5::eth::MacAddr match(const satcat5::eth::ArpHeader& hdr) const;

            bool send_internal(u16 opcode,
                const satcat5::eth::VlanTag& vtag,
                const satcat5::eth::MacAddr& dst,
                const satcat5::eth::MacAddr& sha,
                const satcat5::ip::Addr& spa,
                const satcat5::eth::MacAddr& tha,
                const satcat5::ip::Addr& tpa) const;

            satcat5::ip::Addr m_ipaddr;
            const satcat5::ip::Table* m_table;
            satcat5::util::List<satcat5::eth::ArpListener> m_listeners;
        };
    }
}
