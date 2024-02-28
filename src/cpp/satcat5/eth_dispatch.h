//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Ethernet protocol dispatcher.

#pragma once

#include <satcat5/ethernet.h>
#include <satcat5/net_core.h>

namespace satcat5 {
    namespace eth {
        // Implemention of "net::Dispatch" for Ethernet frames.
        class Dispatch final
            : public satcat5::net::Dispatch
            , public satcat5::io::EventListener
        {
        public:
            // Connect to any valid I/O source and sink.
            // (e.g., satcat5::port::MailMap or satcat5::eth::SlipCodec.)
            // If provided, optional timer object allows retry-timeout.
            Dispatch(
                const satcat5::eth::MacAddr& addr,
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src,
                satcat5::util::GenericTimer* timer = 0);
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            // Write Ethernet frame header and get Writeable object.
            // Variants for reply (required) and any address (optional)
            satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned len) override;
            #if SATCAT5_VLAN_ENABLE
            satcat5::io::Writeable* open_write(
                const satcat5::eth::MacAddr& dst,
                const satcat5::eth::MacType& type,
                satcat5::eth::VlanTag vtag = satcat5::eth::VTAG_NONE);
            #else
            satcat5::io::Writeable* open_write(
                const satcat5::eth::MacAddr& dst,
                const satcat5::eth::MacType& type);
            #endif

            // Set the local MAC-address.
            void set_macaddr(const satcat5::eth::MacAddr& macaddr);

            // Other accessors:
            inline satcat5::eth::MacAddr macaddr() const
                {return m_addr;}
            inline satcat5::eth::MacAddr reply_mac() const
                {return m_reply_macaddr;}
            #if SATCAT5_VLAN_ENABLE
            inline satcat5::eth::VlanTag reply_vtag() const
                {return m_reply_vtag;}
            inline void set_default_vid(const satcat5::eth::VlanTag& vtag)
                {m_default_vid.value = vtag.vid();}
            #endif



        protected:
            // Event handler for incoming Ethernet frames.
            void data_rcvd() override;

            // MAC address for this interface.
            satcat5::eth::MacAddr m_addr;

            // Sink and source objects for the Ethernet interface.
            satcat5::io::Writeable* const m_dst;
            satcat5::io::Readable* const m_src;
            satcat5::util::GenericTimer* const m_timer;

            // Other internal state:
            satcat5::eth::MacAddr m_reply_macaddr;  // Reply address
            #if SATCAT5_VLAN_ENABLE
            satcat5::eth::VlanTag m_reply_vtag;     // Reply VLAN
            satcat5::eth::VlanTag m_default_vid;    // Default VID (optional)
            #endif
        };
    }
}
