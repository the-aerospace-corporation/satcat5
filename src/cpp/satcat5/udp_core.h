//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Type definitions for UDP datagrams and protocol handlers

#pragma once

#include <satcat5/ip_address.h>
#include <satcat5/net_core.h>

namespace satcat5 {
    namespace udp {
        // Alias for address and port types in the "udp" namespace.
        typedef satcat5::ip::Addr Addr;
        typedef satcat5::ip::Port Port;

        //! Well-known UDP port-numbers used by SatCat5:
        //! https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers#Well-known_ports
        //!@{
        constexpr satcat5::udp::Port PORT_NONE          = {0};
        constexpr satcat5::udp::Port PORT_ECHO          = {7};
        constexpr satcat5::udp::Port PORT_DHCP_SERVER   = {67};
        constexpr satcat5::udp::Port PORT_DHCP_CLIENT   = {68};
        constexpr satcat5::udp::Port PORT_TFTP_SERVER   = {69};
        constexpr satcat5::udp::Port PORT_NTP_SERVER    = {123};
        constexpr satcat5::udp::Port PORT_PTP_EVENT     = {319};
        constexpr satcat5::udp::Port PORT_PTP_GENERAL   = {320};
        constexpr satcat5::udp::Port PORT_COAP          = {5683};
        //!@}

        //! Default UDP port-numbers for SatCat5 services:
        //!@{
        constexpr satcat5::udp::Port PORT_CFGBUS_CMD    = {0x5A61};
        constexpr satcat5::udp::Port PORT_CFGBUS_ACK    = {0x5A62};
        constexpr satcat5::udp::Port PORT_CBOR_TLM      = {0x5A63};
        //!@}

        //! Reserved UDP multicast addresses.
        constexpr satcat5::ip::Addr MULTICAST_COAP(224, 0, 1, 187);

        //! Implementation of "net::Address" for UDP Dispatch.
        class Address final : public satcat5::net::Address {
        public:
            //! Connect through the specified UDP interface.
            //! The upstream interface may be null. \see init.
            //! \param iface Pointer to the upstream UDP interface.
            explicit Address(satcat5::udp::Dispatch* iface);
            ~Address() {}

            //! Deferred initialization of the upstream interface.
            //! Used infrequently. If the constructor's interface argument is
            //! null, use this method to later assign the upstream interface.
            void init(satcat5::udp::Dispatch* iface);

            //! Manual address resolution (user supplies IP + MAC).
            void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::eth::MacAddr& dstmac,
                const satcat5::udp::Port& dstport,
                const satcat5::udp::Port& srcport = satcat5::udp::PORT_NONE,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            //! Automatic address resolution (user supplies IP only).
            //! \see ip_core.h or ip::Address for more information.
            void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport,
                const satcat5::udp::Port& srcport = satcat5::udp::PORT_NONE,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            // Required overrides from net::Address.
            void close() override {m_addr.close();}
            bool ready() const override {return m_addr.ready();}
            void retry() override {m_addr.retry();}
            satcat5::net::Dispatch* iface() const override;
            satcat5::io::Writeable* open_write(unsigned len) override;
            bool is_multicast() const override
                {return m_addr.is_multicast();}
            bool matches_reply_address() const override;
            bool reply_is_multicast() const override
                { return m_addr.reply_is_multicast(); }
            void save_reply_address() override;

            // Various accessors.
            inline satcat5::ip::Addr dstaddr() const
                {return m_addr.dstaddr();}
            inline satcat5::eth::MacAddr dstmac() const
                {return m_addr.dstmac();}
            inline satcat5::udp::Port dstport() const
                {return m_dstport;}
            inline satcat5::ip::Addr gateway() const
                {return m_addr.gateway();}
            inline satcat5::udp::Port srcport() const
                {return m_srcport;}
            inline satcat5::udp::Dispatch* udp() const
                {return m_iface;}
            inline satcat5::eth::VlanTag vtag() const
                {return m_addr.vtag();}

        protected:
            satcat5::udp::Dispatch* m_iface;
            satcat5::ip::Address m_addr;
            satcat5::udp::Port m_dstport;
            satcat5::udp::Port m_srcport;
        };

        //! Inheritable container for a udp::Address.
        //! Simple wrapper for Address class, provided to allow control of
        //! multiple-inheritance initialization order (e.g., udp::Socket).
        class AddressContainer {
        public:
            // Various accessors.
            inline satcat5::ip::Addr dstaddr() const
                {return m_addr.dstaddr();}
            inline satcat5::eth::MacAddr dstmac() const
                {return m_addr.dstmac();}
            inline satcat5::udp::Port dstport() const
                {return m_addr.dstport();}
            inline satcat5::ip::Addr gateway() const
                {return m_addr.gateway();}
            inline satcat5::udp::Port srcport() const
                {return m_addr.srcport();}

        protected:
            explicit AddressContainer(satcat5::udp::Dispatch* iface)
                : m_addr(iface) {}
            ~AddressContainer() {}
            satcat5::udp::Address m_addr;
        };

        //! UDP header contents.
        //! The UDP checksum field is never used.
        struct Header {
            // UDP header fields.
            satcat5::udp::Port src;     //!< Source port
            satcat5::udp::Port dst;     //!< Destination port
            u16 length;                 //!< Length of contained data

            //! Write UDP header to the designated stream.
            //! The checksum field will be written as zero (disabled).
            void write_to(satcat5::io::Writeable* wr) const;

            //! Read UDP header from the designated stream.
            //! \returns True on success, false otherwise.
            bool read_from(satcat5::io::Readable* rd);
        };

        constexpr satcat5::udp::Header HEADER_EMPTY =
            {satcat5::udp::PORT_NONE, satcat5::udp::PORT_NONE, 0};
    }
}
