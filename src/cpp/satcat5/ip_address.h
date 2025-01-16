//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// IPv4 address with automatic or manual MAC-address resolution

#pragma once

#include <satcat5/eth_arp.h>
#include <satcat5/net_core.h>
#include <satcat5/timeref.h>

namespace satcat5 {
    namespace ip {
        // Implementation of "net::Address" for IP Dispatch.
        //
        // In manual mode, the user may specify both MAC and IP addresses.
        // In normal usage, it automatically issues ARP request(s) and
        // handles ARP/ICMP messages to determine the correct next-hop
        // gateway and then resolve that gateway's MAC address.
        //
        // The process requires an initial guess for the gateway IP:
        // * If the destination is on the same LAN, or the next-hop router
        //   supports proxy-ARP, then the gateway is the destination IP.
        // * Otherwise, specify the next-hop router IP-address (if known).
        // * Otherwise, specify the default gateway.
        class Address final
            : public satcat5::net::Address
            , public satcat5::eth::ArpListener
        {
        public:
            Address(satcat5::ip::Dispatch* iface, u8 proto);
            ~Address() SATCAT5_OPTIONAL_DTOR;

            // Automatic address resolution using routing table + ARP.
            void connect(
                const satcat5::ip::Addr& dstaddr,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            // Manual address resolution (user supplies IP + MAC)
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

            satcat5::ip::Dispatch* const m_iface;
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
