//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// UDP Dispatcher sorts incoming messages by port index

#pragma once

#include <satcat5/ip_dispatch.h>
#include <satcat5/udp_core.h>

namespace satcat5 {
    namespace udp {
        //! Dispatcher sorts incoming UDP messages by port index.
        //! Implementation of "net::Dispatch" for UDP datagrams,
        //! which accepts incoming packets from IP-dispatch.
        class Dispatch final
            : public satcat5::net::Protocol
            , public satcat5::net::Dispatch
        {
        public:
            //! Attach this protocol handler to the parent interface.
            Dispatch(satcat5::ip::Dispatch* iface);
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            //! Reply to the sender of the most recent received message.
            //! Gets Writeable object for deferred write of IPv4 frame header.
            //! Note: Argument "type" is ignored for UDP replies.
            satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned nbytes) override;

            //! Send a datagram to the designated UDP address and port.
            //! Gets Writeable object for deferred write of IPv4 frame header.
            satcat5::io::Writeable* open_write(
                satcat5::ip::Address& addr,         // Destination IP+MAC
                const satcat5::udp::Port& src,      // Source port
                const satcat5::udp::Port& dst,      // Destination port
                unsigned len);                      // Length after UDP header

            // Other accessors.
            inline satcat5::eth::ProtoArp* arp() const
                {return &m_iface->m_arp;}
            inline satcat5::ip::Dispatch* iface() const
                {return m_iface;}
            inline satcat5::ip::Addr ipaddr() const
                {return m_iface->ipaddr();}
            inline satcat5::eth::MacAddr macaddr() const
                {return m_iface->macaddr();}
            inline satcat5::eth::VlanTag reply_vtag() const
                { return m_iface->reply_vtag(); }
            inline satcat5::eth::MacAddr reply_mac() const
                {return m_iface->reply_mac();}
            inline bool reply_is_multicast() const
                {return m_iface->reply_is_multicast();}
            inline satcat5::ip::Addr reply_ip() const
                {return m_iface->reply_ip();}
            inline satcat5::udp::Port reply_src() const
                {return m_reply_src;}
            inline satcat5::udp::Port reply_dst() const
                {return m_reply_dst;}

            //! Get the next unclaimed dynamically-allocated port index.
            satcat5::udp::Port next_free_port();

        protected:
            // Event handler for incoming IPv4 frames.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Pointer to the parent interface.
            satcat5::ip::Dispatch* const m_iface;

            // Next dynamically assigned port.
            u16 m_next_port;

            // The current reply parameters.
            satcat5::udp::Port m_reply_src;
            satcat5::udp::Port m_reply_dst;
        };
    }
}
