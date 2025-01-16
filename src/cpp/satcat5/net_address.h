//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Generic network Address API
//!

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace net {
        //! Defines a generic API for sending data to a specific destination,
        //! such as a MAC address, IP, or Port.
        //!
        //! Each Address object wraps a particular
        //! net::Dispatch + net::Address + net::Type, to provide an
        //! `open_write()` method for generic net::Protocols. Every
        //! net::Dispatch implementation SHOULD provide a net::Address wrapper.
        //!
        //! Implementations are available for sending data to a:
        //!  * MAC address (eth::Address)
        //!  * IP address (ip::Address)
        //!  * UDP endpoint, i.e., an IP address and port number (udp::Address)
        //!
        //! Implementations MUST derive from this class. The child class also
        //! maintains any required state for opening and closing connections.
        class Address {
        public:
            //! Fetch a pointer to the underlying interface.
            //! Child MUST override this method.
            virtual satcat5::net::Dispatch* iface() const = 0;

            //! Open a new frame to the designated address and type.
            //! Child MUST override this method.
            //! \returns Zero if sending a frame is not currently possible.
            virtual satcat5::io::Writeable* open_write(unsigned len) = 0;

            //! Close any open connections and revert to idle.
            //! Child MUST override this method.
            virtual void close() = 0;

            //! Is this address object ready for use?
            //! Child MUST override this method.
            virtual bool ready() const = 0;

            //! If this Address is not in the ready() state, reattempt any
            //! steps required to do so, such as MAC address resolution.
            //! Child SHOULD override this method if applicable.
            virtual void retry() {}     // GCOVR_EXCL_LINE

            //! Is the destination a broadcast or multicast address?
            //! Child MUST override these method.
            virtual bool is_multicast() const = 0;

            //! Does this Address object match the parent interface's current
            //! reply address? Multicast destinations should match any source
            //! address expected to receive the multicast message.
            //! Child MUST override this method.
            virtual bool matches_reply_address() const = 0;

            //! Was the parent interface's incoming message sent to a multicast
            //! address? (i.e., Could that message have many other recipients?)
            //! Child MUST override this method.
            virtual bool reply_is_multicast() const = 0;

            //! Bind this Address object to the parent interface's current
            //! reply address, as provided in net::Dispatch::open_reply().
            //! Child MUST override this method.
            virtual void save_reply_address() = 0;

            //! All-in-one call that writes an entire packet. Equivalent to
            //! open_write(), io::Writeable::write_bytes(),
            //! io::Writeable::write_finalize().
            bool write_packet(unsigned nbytes, const void* data);
        };
    }
}
