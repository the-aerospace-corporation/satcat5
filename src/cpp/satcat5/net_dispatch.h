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
// Generic network Dispatch API
//
// The "Dispatch" is a generic interface that knows how to read a designated
// protocol layer and sort incoming packets to one of several protocols.
//
// For example, the udp::Dispatch class (udp_dispatch.h) sorts packets by
// the UDP destination port.
//
// Most Dispatch implementations, including eth::Dispatch and ip::Dispatch,
// further provide a means for Protocols to send messages to an arbitrary
// address.  However, this requires protocol-specific arguments that cannot
// be provided in the generic API.
//

#pragma once

#include <satcat5/list.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace net {
        // Network "Dispatch" objects:
        //  * Know their own address, and any other required parameters.
        //  * Allow registration of one or more Protocols, each tied to a
        //    specific traffic stream (e.g., an EtherType or UDP port).
        //  * Allow construction of Filters that designate
        //  * Accept incoming frames and read header information.
        //  * Apply filtering as needed for invalid frame headers.
        //  * Route the remaining data to one of several Protocol objects,
        //    comparing header field(s) until a suitable match is found.
        //  * Allow Protocol objects to send simple replies.
        class Dispatch {
        public:
            // Open a reply to the sender of the most recent message, by
            // writing frame header(s) and returning a stream where the
            // caller should write frame data, then call write_finalize().
            //
            // The length argument is the number of bytes that will be written
            // by the caller. (IPv4 and UDP require this information up-front.)
            //
            // Returns zero if sending a reply is not currently possible.
            //
            // Child MUST implement this method.
            // Child SHOULD also provide an equivalent open_write(...) method
            //  for sending messages to other recipients, when practical.
            // Child MAY ignore the "type" argument at its discretion.
            virtual satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned len) = 0;

            // Register or unregister a Protocol object.
            inline void add(satcat5::net::Protocol* proto)
                {m_list.add(proto);}
            inline void remove(satcat5::net::Protocol* proto)
                {m_list.remove(proto);}

            // Check if a given Type has a matching Protocol.
            bool bound(const satcat5::net::Type& type) const;

        protected:
            // Constructor and destructor access restricted to children.
            Dispatch() {}
            ~Dispatch() {}

            // Deliver current message by calling Protocol::frame_rcvd(...).
            // Returns true if a matching Protocol is found.
            // Note: Caller is responsible for read_finalize(), if required.
            bool deliver(
                const satcat5::net::Type& type,
                satcat5::io::Readable* src, unsigned len);

            // Linked list of protocol objects.
            satcat5::util::List<satcat5::net::Protocol> m_list;
        };
    }
}
