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
// Sending packets to a specific Ethernet address
//
// This file defines an child of net::Address that can send packets to
// a designated MAC-address and EtherType.
//

#pragma once

#include <satcat5/eth_header.h>
#include <satcat5/net_address.h>

namespace satcat5 {
    namespace eth {
        // Implementation of "net::Address" for Ethernet Dispatch.
        class Address : public satcat5::net::Address {
        public:
            explicit Address(satcat5::eth::Dispatch* iface);

            #if SATCAT5_VLAN_ENABLE
            void connect(
                const satcat5::eth::MacAddr& addr,
                const satcat5::eth::MacType& type,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);
            #else
            void connect(
                const satcat5::eth::MacAddr& addr,
                const satcat5::eth::MacType& type);
            #endif

            satcat5::net::Dispatch* iface() const override;
            satcat5::io::Writeable* open_write(unsigned len) override;
            void close() override;
            bool ready() const override;

        protected:
            satcat5::eth::Dispatch* const m_iface;
            satcat5::eth::MacAddr m_addr;
            satcat5::eth::MacType m_type;
            #if SATCAT5_VLAN_ENABLE
            satcat5::eth::VlanTag m_vtag;
            #endif
        };

        // Simple wrapper for Address class, provided to allow control of
        // multiple-inheritance initialization order (e.g., eth::Socket).
        class AddressContainer {
        protected:
            explicit AddressContainer(satcat5::eth::Dispatch* iface)
                : m_addr(iface) {}
            ~AddressContainer() {}
            satcat5::eth::Address m_addr;
        };
    }
}
