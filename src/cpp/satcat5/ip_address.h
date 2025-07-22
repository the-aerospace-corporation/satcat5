//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// IPv4 address with automatic or manual MAC-address resolution

#pragma once

#include <satcat5/eth_arp.h>
#include <satcat5/net_core.h>
#include <satcat5/timeref.h>

namespace satcat5 {
    namespace ip {
        //! Connection metadata for an IPv4 address.
        //! This class stores all required metadata required to reach a
        //! specified IPv4 address, including MAC address and VLAN tags.
        //! This is in contrast with the barebones ip::Addr object, which
        //! stores only the destination IPv4 address as a 32-bit integer.
        //!
        //! The ip::Address class implements the full `net::Address` API.
        //! To send an IPv4 datagram to the specified address, call the
        //! `open_write` method, then write and finalize packet contents.
        //!
        //! In manual mode, the user specifies both MAC and IP addresses.
        //! In automatic mode, this class automatically issues queries the
        //! routing table and ARP cache (ip::Table).  If the next-hop MAC
        //! address is not cached, it automatically issues an ARP request.
        //!
        //! Once created, the ip::Address object also tracks related ICMP
        //! requests, such as redirects forwarding traffic to a different
        //! next-hop gateway address, repeating MAC resolution as needed.
        class Address final
            : public satcat5::net::Address
            , public satcat5::eth::ArpListener
        {
        public:
            //! Create this object and bind it to a network interface.
            //! The upstream interface may be null. \see init.
            //! \param iface Pointer to the upstream IP interface.
            //! \param proto IPv4 protocol number, such as ip::PROTO_UDP.
            Address(satcat5::ip::Dispatch* iface, u8 proto);
            ~Address() SATCAT5_OPTIONAL_DTOR;

            //! Deferred initialization of the upstream interface.
            //! Used infrequently. If the constructor's interface argument is
            //! null, use this method to later assign the upstream interface.
            void init(satcat5::ip::Dispatch* iface);

            //! Automatic address resolution using routing table + ARP.
            void connect(
                const satcat5::ip::Addr& dstaddr,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            //! Manual address resolution, user supplies IP + MAC.
            void connect(
                const satcat5::ip::Addr& dstaddr,
                const satcat5::eth::MacAddr& dstmac,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            // Required overrides from net::Address:
            void close() override;
            bool ready() const override {return m_ready;}
            void retry() override;
            satcat5::net::Dispatch* iface() const override;
            satcat5::io::Writeable* open_write(unsigned len) override;
            bool is_multicast() const override;
            bool matches_reply_address() const override;
            bool reply_is_multicast() const override;
            void save_reply_address() override;

            // Various accessors.
            satcat5::eth::MacAddr dstmac() const {return m_dstmac;}
            satcat5::eth::VlanTag vtag() const {return m_vtag;}
            satcat5::ip::Addr dstaddr() const {return m_dstaddr;}
            satcat5::ip::Addr gateway() const {return m_gateway;}

        protected:
            void arp_event(
                const satcat5::eth::MacAddr& mac,
                const satcat5::ip::Addr& ip) override;
            void gateway_change(
                const satcat5::ip::Addr& dstaddr,
                const satcat5::ip::Addr& gateway) override;

            satcat5::ip::Dispatch* m_iface;
            const u8 m_proto;
            u8 m_ready;
            satcat5::util::TimeVal m_arp_tref;
            satcat5::eth::MacAddr m_dstmac;
            satcat5::ip::Addr m_dstaddr;
            satcat5::ip::Addr m_gateway;
            satcat5::eth::VlanTag m_vtag;
        };
    }
}
