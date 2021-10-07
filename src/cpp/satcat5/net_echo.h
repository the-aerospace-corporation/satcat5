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
// Generic Echo service
//
// The Echo protocol can be attached to any Dispatch object.  It copies
// each received frame back to the original sender.  Variants are provided
// for raw-Ethernet and UDP networking.
//

#pragma once

#include <satcat5/ethernet.h>
#include <satcat5/udp_core.h>

namespace satcat5 {
    namespace net {
        // Generic version requires a wrapper to be used.
        class ProtoEcho : public satcat5::net::Protocol {
        protected:
            // Only children can safely access constructor/destructor.
            ProtoEcho(
                satcat5::net::Dispatch* iface,
                const satcat5::net::Type& type_req,
                const satcat5::net::Type& type_ack);
            ~ProtoEcho() SATCAT5_OPTIONAL_DTOR;

            // Event handler for incoming frames.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            satcat5::net::Dispatch* const m_iface;
            satcat5::net::Type const m_replytype;
        };
    }

    // Thin wrappers for commonly used protocols:
    namespace eth {
        // Note: Always use different request/reply EtherTypes to
        //       avoid the potential for infinite reply loops.
        class ProtoEcho : public satcat5::net::ProtoEcho {
        public:
            ProtoEcho(
                satcat5::eth::Dispatch* iface,
                satcat5::eth::MacType type_req,
                satcat5::eth::MacType type_ack);
        };
    }

    namespace udp {
        class ProtoEcho : public satcat5::net::ProtoEcho {
        public:
            ProtoEcho(
                satcat5::udp::Dispatch* iface,
                satcat5::udp::Port port = satcat5::udp::PORT_ECHO);
        };
    }
}
