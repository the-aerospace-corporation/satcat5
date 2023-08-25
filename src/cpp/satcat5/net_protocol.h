//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
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
// Generic network Protocol API
//
// A net::Protocol is the counterpart to net::Dispatch. The Dispatch layer
// maintains a list of active Protocols, and inspects each incoming packet to
// route it to the appropriate destination.
//
// Protocols may be endpoints with application-layer functionality.  They may
// also be middleware that does additional sorting. e.g., The udp::Dispatch
// class is both a Protocol (it accepts all UDP traffic from ip::Dispatch)
// and a Dispatch (it routes UDP packets to the appropriate port).
//

#pragma once

#include <satcat5/io_readable.h>
#include <satcat5/net_type.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace net {
        // Each Protocol handles a particular data stream (see net_dispatch.h).
        class Protocol {
        public:
            // Dispatch calls frame_rcvd(...) for each incoming frame with
            // with a matching Type value.  The child class SHOULD read
            // the frame contents from the provided "src" object, which
            // is only valid until the function returns.
            //
            // To send a reply:
            //  * Call m_iface->open_reply() to obtain a Writable object.
            //    (This also writes out any applicable frame headers.)
            //  * Write frame contents, then call write_finalize().
            //
            // The child class MUST override this method.
            virtual void frame_rcvd(satcat5::io::LimitedRead& src) = 0;

        protected:
            // Constructor and destructor access restricted to children.
            // Note: Child MUST call Dispatch::add and Dispatch::remove.
            explicit Protocol(const satcat5::net::Type& type)
                : m_filter(type), m_next(0) {}
            ~Protocol() {}

            satcat5::net::Type m_filter;        // Incoming packet filter

        private:
            // Required objects for net::Dispatch.
            friend satcat5::net::Dispatch;
            friend satcat5::util::ListCore;
            satcat5::net::Protocol* m_next;     // Linked list of Protocols
        };
    }
}
