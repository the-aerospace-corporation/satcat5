//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Deferred packet forwarding for the IPv4 router

#pragma once

#include <satcat5/eth_arp.h>
#include <satcat5/eth_switch.h>
#include <satcat5/ip_core.h>
#include <satcat5/list.h>
#include <satcat5/timeref.h>

namespace satcat5 {
    namespace router2 {
        //! State information for a single deferred packet.
        //! \see satcat5::router2::DeferFwd
        struct DeferPkt {
        public:
            // All data and metadata are public variables:
            satcat5::io::MultiPacket* pkt;  //!< Packet object
            satcat5::ip::Addr dst_ip;       //!< Destination address
            SATCAT5_PMASK_TYPE dst_mask;    //!< Destination port-mask
            u16 sent;                       //!< Number of attempts so far
            u16 trem;                       //!< Remaining time in msec

            //! Reconstitute switch PacketMeta from this object.
            bool read_meta(satcat5::eth::PluginPacket& meta);

        private:
            // Linked list to the next packet object.
            friend satcat5::util::ListCore;
            satcat5::router2::DeferPkt* m_next;
        };

        //! Deferred packet-forwarding system for the IPv4 router.
        //!
        //! To forward each packet, the router must determine the MAC address
        //! for the next hop in the chain.  If that information is not already
        //! present in the combined CIDR/ARP table, then the router must defer
        //! forwarding until the ARP query/response is completed.
        //!
        //! The router2::DeferFwd class implements deferred forwarding, retaining
        //! packet pointers from the router's primary MultiBuffer.  Most incoming
        //! packets trigger an ARP query; the packet can be forwarded after a
        //! matching ARP response.  If there is no response, then the query is
        //! repeated with an increasing timeout. After several failed attempts,
        //! undeliverable packets trigger an ICMP error to the original sender.
        class DeferFwd
            : public satcat5::eth::ArpListener
            , public satcat5::poll::Timer
        {
        public:
            //! Accept this packet into the queue?
            bool accept(const satcat5::eth::PluginPacket& meta);

        protected:
            //! Constructor should only be accessed by children, and
            //! requires a backing array of empty DeferPkt objects.
            DeferFwd(
                satcat5::router2::Dispatch* parent,
                satcat5::router2::DeferPkt* buff,
                unsigned bcount);
            ~DeferFwd() SATCAT5_OPTIONAL_DTOR;

            // Event handler callbacks.
            void arp_event(
                const satcat5::eth::MacAddr& mac,
                const satcat5::ip::Addr& ip) override;
            void timer_event() override;

            // Packet handlers may mutate the active list,
            // so they return the next item to be processed.
            satcat5::router2::DeferPkt* request_arp(
                satcat5::router2::DeferPkt* pkt);
            satcat5::router2::DeferPkt* request_fwd(
                satcat5::router2::DeferPkt* pkt, const satcat5::eth::MacAddr& dst);

            // Pointers to upstream interface objects.
            satcat5::router2::Dispatch* const m_parent;
            satcat5::eth::ProtoArp* m_arp;

            // Reference for measuring elapsed time.
            satcat5::util::TimeVal m_tref;

            // Lists for empty and active packets.
            satcat5::util::List<satcat5::router2::DeferPkt> m_active;
            satcat5::util::List<satcat5::router2::DeferPkt> m_empty;
        };

        //! Implement DeferFwd with static memory allocation.
        //! \see satcat5::router2::DeferFwd
        template <unsigned SIZE = SATCAT5_MBUFF_RXPKT>
        class DeferFwdStatic final : public satcat5::router2::DeferFwd {
        public:
            //! Constructor links the parent interface and the backing array.
            explicit DeferFwdStatic(satcat5::router2::Dispatch* parent)
                : DeferFwd(parent, m_buff, SIZE), m_buff{} {}

        protected:
            // Backing array for parent (i.e., m_active and m_empty).
            satcat5::router2::DeferPkt m_buff[SIZE];
        };
    }
}
