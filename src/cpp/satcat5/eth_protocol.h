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
