//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Generic network Address API
//
// The "Address" class defines a generic API for sending data to a specific
// destination.  Implementations are available for sending data to a:
//  * MAC address(eth_address.h)
//  * IP address (ip_address.h)
//  * UDP endpoint, i.e., an IP address and port number (udp_address.h)
//
// Implementations must derive from this class. The child class also
// maintains any required state for opening and closing connections.
//

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace net {
        // Each Address object wraps a particular Dispatch + Address + Type,
        // to provide an open_write(...) method for generic Protocols.
        // Every Dispatch implementation SHOULD provide an Address wrapper.
        class Address {
        public:
            // Fetch a pointer to the underlying interface.
            // Child MUST override this method.
            virtual satcat5::net::Dispatch* iface() const = 0;

            // Open a new frame to the designated address and type.
            // Returns zero if sending a frame is not currently possible.
            // Child MUST override this method.
            virtual satcat5::io::Writeable* open_write(unsigned len) = 0;

            // Close any open connections and revert to idle.
            // Child MUST override this method.
            virtual void close() = 0;

            // Is this address object ready for use?
            // Child MUST override this method.
            virtual bool ready() const = 0;

            // All-in-one call that writes an entire packet.
            // (Equivalent to open_write, write_bytes, write_finalize.)
            bool write_packet(unsigned nbytes, const void* data);
        };
    }
}
