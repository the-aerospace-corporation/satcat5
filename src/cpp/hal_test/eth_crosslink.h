//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Crosslink between two simulated Ethernet interfaces.
// Includes variants with and without a full IPv4 stack.

#pragma once

#include <hal_test/eth_interface.h>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/ip_stack.h>

namespace satcat5 {
    namespace test {
        // Container for a pair of back-to-back Ethernet interfaces.
        struct Crosslink
        {
            // Set preferred address for each interface.
            static constexpr satcat5::eth::MacAddr
                MAC0 = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11},
                MAC1 = {0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22};
            static constexpr satcat5::ip::Addr
                IP0 = satcat5::ip::Addr(192, 168, 1, 11),
                IP1 = satcat5::ip::Addr(192, 168, 1, 74);

            // Define each Ethernet interface.
            Crosslink();
            satcat5::test::EthernetInterface eth0;
            satcat5::test::EthernetInterface eth1;

            // Shortcut for setting loss rate on both interfaces.
            void set_loss_rate(float rate);
        };

        // Crosslink plus Ethernet dispatch.
        struct CrosslinkEth : public satcat5::test::Crosslink
        {
            CrosslinkEth();
            satcat5::eth::Dispatch net0;
            satcat5::eth::Dispatch net1;
        };

        // Crosslink plus full IPv4+UDP stack.
        struct CrosslinkIp : public satcat5::test::Crosslink
        {
            CrosslinkIp();
            satcat5::test::FastPosixTimer clock;
            satcat5::ip::Stack net0;
            satcat5::ip::Stack net1;
        };
    }
}
