//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Crosslink between two simulated Ethernet interfaces.
// Includes variants with and without a full IPv4 stack.

#pragma once

#include <hal_posix/file_pcap.h>
#include <hal_posix/posix_utils.h>
#include <hal_test/eth_interface.h>
#include <hal_test/sim_utils.h>
#include <satcat5/ccsds_spp.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/ip_stack.h>

namespace satcat5 {
    namespace test {
        // Container for a pair of back-to-back network interfaces.
        // (Default assumes Ethernet, but it can simulate others.)
        struct Crosslink
        {
            // Set preferred address for each interface.
            static constexpr satcat5::eth::MacAddr
                MAC0 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}},
                MAC1 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}};
            static constexpr satcat5::ip::Addr
                IP0 = satcat5::ip::Addr(192, 168, 1, 11),
                IP1 = satcat5::ip::Addr(192, 168, 1, 74);

            // Constructor accepts a filename to use for packet logging.
            // (Passing null or empty string disables this option.)
            explicit Crosslink(const char* filename,
                u16 type = satcat5::io::LINKTYPE_ETHERNET);

            // Packet-capture logging.
            satcat5::test::TimerSimulation timer;
            satcat5::io::WritePcap pcap;

            // Define each network interface (usually Ethernet).
            satcat5::test::EthernetInterface eth0;
            satcat5::test::EthernetInterface eth1;

            // Shortcut for setting loss rate on both interfaces.
            void set_loss_rate(float rate);
        };

        // Crosslink plus Ethernet dispatch.
        struct CrosslinkEth : public satcat5::test::Crosslink
        {
            explicit CrosslinkEth(const char* filename = 0);
            satcat5::eth::Dispatch net0;
            satcat5::eth::Dispatch net1;
        };

        // Crosslink plus full IPv4+UDP stack.
        struct CrosslinkIp : public satcat5::test::Crosslink
        {
            explicit CrosslinkIp(const char* filename = 0);
            satcat5::ip::Stack net0;
            satcat5::ip::Stack net1;
        };

        // Crosslink plus CCSDS-SPP dispatch.
        struct CrosslinkSpp : public satcat5::test::Crosslink
        {
            explicit CrosslinkSpp(const char* filename = 0);
            satcat5::ccsds_spp::Dispatch spp0;
            satcat5::ccsds_spp::Dispatch spp1;
        };
    }
}
