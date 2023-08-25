//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2023 The Aerospace Corporation
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
// UDP Dispatcher sorts incoming messages by port index

#pragma once

#include <satcat5/ip_dispatch.h>
#include <satcat5/udp_core.h>

namespace satcat5 {
    namespace udp {
        // Implementation of "net::Dispatch" for UDP datagrams,
        // which accepts incoming packets from IP-dispatch.
        class Dispatch final
            : public satcat5::net::Protocol
            , public satcat5::net::Dispatch
        {
        public:
            Dispatch(satcat5::ip::Dispatch* iface);
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            // Get Writeable object for deferred write of IPv4 frame header.
            // Variants for reply (required) and any address (optional)
            // Note: Argument "type" is ignored for UDP replies.
            satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned nbytes) override;
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
            inline satcat5::eth::MacAddr reply_mac() const
                {return m_iface->reply_mac();}
            inline satcat5::ip::Addr reply_ip() const
                {return m_iface->reply_ip();}

            // Get the next unclaimed dynamically-allocated port index.
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
