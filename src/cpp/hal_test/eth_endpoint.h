//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Simulated Ethernet endpoint for use with MailAdapter and SlipAdapter

#pragma once

#include <hal_posix/posix_utils.h>
#include <satcat5/eth_checksum.h>
#include <satcat5/io_throttle.h>
#include <satcat5/ip_stack.h>

namespace satcat5 {
    namespace test {
        // This object represents a simulated device with an IP/UDP stack and
        // a network interface controller (NIC) with a controlled I/O rate.
        // The read/write interface of the top-level object represents the
        // switch-side PHY.  The object contains the device-side PHY, the
        // endpoint device itself, and the associated network stack.
        // Note: Recommend "test::TimerSimulation" for the timer object.
        class EthernetEndpoint final
            : public satcat5::io::ReadableRedirect      // From device to network
            , public satcat5::io::WriteableRedirect     // From network to device
        {
        public:
            explicit EthernetEndpoint(
                const satcat5::eth::MacAddr& local_mac, // Local MAC address
                const satcat5::ip::Addr& local_ip,      // Local IP address
                unsigned rate_bps = 1000000000);        // Line rate (bits/sec)

            void set_rate(unsigned rate_bps);
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

        protected:
            // Rx chain (net to dev): Write top -> rxlimit -> rxbuff -> Read by m_ip
            // Tx chain (dev to net): Write by m_ip -> txlimit -> txbuff -> Read top
            satcat5::io::PacketBufferHeap m_rxbuff;     // From network to device
            satcat5::io::PacketBufferHeap m_txbuff;     // From device to network
            satcat5::io::WriteableThrottle m_rxlimit;   // From network to device
            satcat5::io::WriteableThrottle m_txlimit;   // From device to network
            satcat5::ip::Stack m_ip;                    // Simulated device/endpoint
        };

        // Same as above, but over-the-wire data is SLIP-encoded.
        class SlipEndpoint
            : public satcat5::io::ReadableRedirect      // From device to network
            , public satcat5::io::WriteableRedirect     // From network to device
        {
        public:
            explicit SlipEndpoint(
                const satcat5::eth::MacAddr& local_mac, // Local MAC address
                const satcat5::ip::Addr& local_ip,      // Local IP address
                unsigned rate_bps = 1000000);           // Line rate (bits/sec)

            inline void set_rate(unsigned rate_bps)
                { m_eth.set_rate(rate_bps); }
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

        protected:
            // SLIP encoder and decoder sits between endpoint and network.
            satcat5::test::EthernetEndpoint m_eth;
            satcat5::eth::SlipCodecInverse m_slip;
        };
    }
}
