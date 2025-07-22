//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Simulated Ethernet endpoints for use in router and switch simulations.

#pragma once

#include <hal_posix/posix_utils.h>
#include <satcat5/eth_checksum.h>
#include <satcat5/io_throttle.h>
#include <satcat5/ip_stack.h>

namespace satcat5 {
    namespace test {
        //! Simulated Ethernet endpoint for use in router and switch simulations.
        //!
        //! This object represents a simulated device with an IP/UDP stack and
        //! a network interface controller (NIC) with a controlled I/O rate.
        //! Unlike test::EthernetInterface, this object automatically attaches
        //! a full Ethernet/IP/UDP network stack. It is typically used in
        //! router or switch simulations with many attached endpoints.
        //!
        //! This version is typically used with port::MailAdapter.  Its input
        //! and output are Ethernet frames, not including the FCS field.
        //!
        //! The read/write interface of the top-level object represents the
        //! switch-side PHY.  The object contains the device-side PHY, the
        //! endpoint device itself, and the associated network stack.
        //!
        //! \see eth::Switch, router2::StackSoftware, port::MailAdapter
        class EthernetEndpoint final
            : public satcat5::io::ReadableRedirect      // From device to network
            , public satcat5::io::WriteableRedirect     // From network to device
        {
        public:
            //! Create and configure this endpoint.
            explicit EthernetEndpoint(
                const satcat5::eth::MacAddr& local_mac, // Local MAC address
                const satcat5::ip::Addr& local_ip,      // Local IP address
                unsigned rate_bps = 1000000000);        // Line rate (bits/sec)

            //! Adjust the throughput-limiter.
            void set_rate(unsigned rate_bps);

            //! Accessors for the internal network stack.
            //!@{
            inline satcat5::ip::Stack& stack()
                { return m_ip; }
            inline satcat5::eth::Dispatch* eth()
                { return &m_ip.m_eth; }
            inline satcat5::ip::Dispatch* ip()
                { return &m_ip.m_ip; }
            inline satcat5::ip::Table* route()
                { return &m_ip.m_route; }
            inline satcat5::udp::Dispatch* udp()
                { return &m_ip.m_udp; }
            inline satcat5::io::Writeable* wr()
                { return &m_txbuff; }
            //!@}

        protected:
            // Rx chain (net to dev): Write top -> rxlimit -> rxbuff -> Read by m_ip
            // Tx chain (dev to net): Write by m_ip -> txlimit -> txbuff -> Read top
            satcat5::io::PacketBufferHeap m_rxbuff;     // From network to device
            satcat5::io::PacketBufferHeap m_txbuff;     // From device to network
            satcat5::io::WriteableThrottle m_rxlimit;   // From network to device
            satcat5::io::WriteableThrottle m_txlimit;   // From device to network
            satcat5::ip::Stack m_ip;                    // Simulated device/endpoint
        };

        //! SLIP-encoded Ethernet endpoint for use in router and switch simulations.
        //! This class is similar to test::EthernetEndpoint, except that its input
        //! and output are SLIP-encoded Ethernet frames that include the FCS field.
        class SlipEndpoint
            : public satcat5::io::ReadableRedirect      // From device to network
            , public satcat5::io::WriteableRedirect     // From network to device
        {
        public:
            //! Create and configure this endpoint.
            explicit SlipEndpoint(
                const satcat5::eth::MacAddr& local_mac, // Local MAC address
                const satcat5::ip::Addr& local_ip,      // Local IP address
                unsigned rate_bps = 1000000);           // Line rate (bits/sec)

            //! Adjust the throughput-limiter.
            inline void set_rate(unsigned rate_bps)
                { m_eth.set_rate(rate_bps); }

            //! Accessors for the internal network stack.
            //!@{
            inline satcat5::ip::Stack& stack()
                { return m_eth.stack(); }
            inline satcat5::eth::Dispatch* eth()
                { return m_eth.eth(); }
            inline satcat5::ip::Dispatch* ip()
                { return m_eth.ip(); }
            inline satcat5::ip::Table* route()
                { return m_eth.route(); }
            inline satcat5::udp::Dispatch* udp()
                { return m_eth.udp(); }
            inline satcat5::io::Writeable* wr()
                { return m_eth.wr(); }
            //!@}

        protected:
            // SLIP encoder and decoder sits between endpoint and network.
            satcat5::test::EthernetEndpoint m_eth;
            satcat5::eth::SlipCodecInverse m_slip;
        };
    }
}
