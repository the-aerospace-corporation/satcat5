//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Implemention of "net::Dispatch" for Ethernet frames.

#pragma once

#include <satcat5/ethernet.h>
#include <satcat5/net_core.h>

namespace satcat5 {
    namespace eth {
        //! Implemention of "net::Dispatch" for Ethernet frames.
        //! This class listens for incoming data, reads the Ethernet frame
        //! header, and forwards the frame to a registered eth::Protocol
        //! based on the EtherType field.
        class Dispatch final
            : public satcat5::net::Dispatch
            , public satcat5::io::EventListener
        {
        public:
            //! Connect this network interface to a valid I/O source and sink.
            //! (e.g., satcat5::port::MailMap or satcat5::eth::SlipCodec.)
            //! If provided, optional timer object allows retry-timeout.
            Dispatch(
                const satcat5::eth::MacAddr& addr,
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            //! Send a reply to the most recent received frame.
            //! Write Ethernet frame header and get Writeable object.
            satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned len) override;

            //! Send a frame to the designated Ethernet address/VLAN.
            //! Write Ethernet frame header and get Writeable object.
            satcat5::io::Writeable* open_write(
                const satcat5::eth::MacAddr& dst,
                const satcat5::eth::MacType& type,
                satcat5::eth::VlanTag vtag = satcat5::eth::VTAG_NONE);

            //! Set the local MAC-address.
            void set_macaddr(const satcat5::eth::MacAddr& macaddr);

            // Other accessors:
            inline satcat5::eth::MacAddr macaddr() const
                { return m_addr; }
            inline satcat5::eth::MacAddr reply_mac() const
                { return m_reply_srcaddr; }
            inline satcat5::eth::MacType reply_type() const
                { return m_reply_type; }
            inline satcat5::eth::VlanTag reply_vtag() const
                { return m_reply_vtag; }
            inline bool reply_is_multicast() const
                { return m_reply_dstaddr.is_multicast(); }
            inline void set_default_vid(const satcat5::eth::VlanTag& vtag)
                { m_default_vid.value = vtag.vid(); }

        protected:
            // Event handler for incoming Ethernet frames.
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;

            // MAC address for this interface.
            satcat5::eth::MacAddr m_addr;

            // Sink and source objects for the Ethernet interface.
            satcat5::io::Writeable* const m_dst;
            satcat5::io::Readable* m_src;

            // Other internal state:
            satcat5::eth::MacAddr m_reply_dstaddr;  // Reply destination MAC
            satcat5::eth::MacAddr m_reply_srcaddr;  // Reply source MAC
            satcat5::eth::MacType m_reply_type;     // Reply EtherType
            satcat5::eth::VlanTag m_reply_vtag;     // Reply VLAN
            satcat5::eth::VlanTag m_default_vid;    // Default VID (optional)
        };
    }
}
