//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
