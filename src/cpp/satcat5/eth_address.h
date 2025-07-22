//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Send packets to a specific Ethernet address.

#pragma once

#include <satcat5/eth_header.h>
#include <satcat5/net_address.h>

namespace satcat5 {
    namespace eth {
        //! Send packets to a specific Ethernet address.
        //! Implementation of `net::Address` for Ethernet Dispatch.
        class Address : public satcat5::net::Address {
        public:
            //! Link this object to a network interface.
            explicit Address(satcat5::eth::Dispatch* iface);

            //! Connect to the designated address.
            void connect(
                const satcat5::eth::MacAddr& addr,
                const satcat5::eth::MacType& type,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            // Required overrides from net::Address:
            satcat5::net::Dispatch* iface() const override;
            satcat5::io::Writeable* open_write(unsigned len) override;
            void close() override;
            bool ready() const override;
            bool is_multicast() const override;
            bool matches_reply_address() const override;
            bool reply_is_multicast() const override;
            void save_reply_address() override;

            // Other accessors.
            inline satcat5::eth::MacAddr dstmac() const
                { return m_addr; }
            inline satcat5::eth::MacType etype() const
                { return m_type; }
            inline satcat5::eth::VlanTag vtag() const
                { return m_vtag; }

        protected:
            satcat5::eth::Dispatch* const m_iface;
            satcat5::eth::MacAddr m_addr;
            satcat5::eth::MacType m_type;
            satcat5::eth::VlanTag m_vtag;
        };

        //! Inheritable container for a eth::Address.
        //! Simple wrapper for Address class, provided to allow control of
        //! multiple-inheritance initialization order (e.g., eth::Socket).
        class AddressContainer {
        protected:
            explicit AddressContainer(satcat5::eth::Dispatch* iface)
                : m_addr(iface) {}
            ~AddressContainer() {}
            satcat5::eth::Address m_addr;
        };
    }
}
