//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Sorting of incoming packets by EtherType.
//
// This file defines a child of net::Protocol (see net_protocol.h) that
// acts as the handler for incoming frames of a specific EtherType.
// (See also: eth_dispatch.h for the corresponding "Dispatch" class.)
//
// The eth::Protocol handles the interface to an eth::Dispatch object.
// The child class must define frame_rcvd(...) to process each packet.
//

#pragma once

#include <satcat5/eth_header.h>
#include <satcat5/net_protocol.h>

namespace satcat5 {
    namespace eth {
        // Ethernet-specific extensions to net::Protocol.
        class Protocol : public satcat5::net::Protocol {
        protected:
            // Register or unregister this handler with the Dispatcher.
            // (Only child can safely call constructor and destructor.)
            Protocol(
                satcat5::eth::Dispatch* dispatch,
                const satcat5::eth::MacType& ethertype);
            #if SATCAT5_VLAN_ENABLE
            Protocol(
                satcat5::eth::Dispatch* dispatch,
                const satcat5::eth::MacType& ethertype,
                const satcat5::eth::VlanTag& vtag);
            #endif
            ~Protocol() SATCAT5_OPTIONAL_DTOR;

            // Note: Child MUST override frame_rcvd(...)
            //  void frame_rcvd(satcat5::io::LimitedRead& src);

            // Parent interface (e.g., for address and I/O)
            satcat5::eth::Dispatch* const m_iface;
            const satcat5::eth::MacType m_etype;
        };
    }
}
