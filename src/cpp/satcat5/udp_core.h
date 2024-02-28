//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
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

        // Well-known UDP port-numbers used by SatCat5:
        // https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers#Well-known_ports
        constexpr satcat5::udp::Port PORT_NONE          = {0};
        constexpr satcat5::udp::Port PORT_ECHO          = {7};
        constexpr satcat5::udp::Port PORT_DHCP_SERVER   = {67};
        constexpr satcat5::udp::Port PORT_DHCP_CLIENT   = {68};
        constexpr satcat5::udp::Port PORT_TFTP_SERVER   = {69};
        constexpr satcat5::udp::Port PORT_PTP_EVENT     = {319};
        constexpr satcat5::udp::Port PORT_PTP_GENERAL   = {320};

        // Default UDP port-numbers for SatCat5 services:
        constexpr satcat5::udp::Port PORT_CFGBUS_CMD    = {0x5A61};
        constexpr satcat5::udp::Port PORT_CFGBUS_ACK    = {0x5A62};
        constexpr satcat5::udp::Port PORT_CBOR_TLM      = {0x5A63};

        // Implementation of "net::Address" for IP Dispatch.
        class Address final : public satcat5::net::Address {
        public:
            explicit Address(satcat5::udp::Dispatch* iface);
            ~Address() {}

            // Manual address resolution (user supplies IP + MAC)
            void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::eth::MacAddr& dstmac,
                const satcat5::udp::Port& dstport,
                const satcat5::udp::Port& srcport);

            // Automatic address resolution (user supplies IP only)
            // See "ip_core.h / ip::Address" for more information.
            void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport,
                const satcat5::udp::Port& srcport);

            // Retry automatic address resolution.
            void retry() {m_addr.retry();}

            // Required overrides from net::Address.
            void close() override {m_addr.close();}
            bool ready() const override {return m_addr.ready();}
            satcat5::net::Dispatch* iface() const override;
            satcat5::io::Writeable* open_write(unsigned len) override;

            // Various accessors.
            inline satcat5::ip::Addr dstaddr() const
                {return m_addr.dstaddr();}
            inline satcat5::udp::Port dstport() const
                {return m_dstport;}
            inline satcat5::ip::Addr gateway() const
                {return m_addr.gateway();}
            inline satcat5::udp::Port srcport() const
                {return m_srcport;}

            // Raw interface object is accessible to public.
            satcat5::udp::Dispatch* const m_iface;

        protected:
            satcat5::ip::Address m_addr;
            satcat5::udp::Port m_dstport;
            satcat5::udp::Port m_srcport;
        };

        // Simple wrapper for Address class, provided to allow control of
        // multiple-inheritance initialization order (e.g., udp::Socket).
        class AddressContainer {
        protected:
            explicit AddressContainer(satcat5::udp::Dispatch* iface)
                : m_addr(iface) {}
            ~AddressContainer() {}
            satcat5::udp::Address m_addr;
        };

        // Checksum field is not used
        struct Header {
            // UDP header fields.
            satcat5::udp::Port src;
            satcat5::udp::Port dst;
            u16 length;

            // Write UDP header to the designated stream.
            void write_to(satcat5::io::Writeable* wr) const;

            // Read UDP header from the designated stream.
            // (Returns true on success, false otherwise.)
            bool read_from(satcat5::io::Readable* rd);
        };

        constexpr satcat5::udp::Header HEADER_EMPTY =
            {satcat5::udp::PORT_NONE, satcat5::udp::PORT_NONE, 0};
    }
}
