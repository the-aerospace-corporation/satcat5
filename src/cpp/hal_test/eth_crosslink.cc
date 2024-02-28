//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_test/eth_crosslink.h>

using satcat5::test::Crosslink;
using satcat5::test::CrosslinkEth;
using satcat5::test::CrosslinkIp;

// Workaround to ensure C++11 allocates static constants.
// See also: https://stackoverflow.com/questions/8452952/
constexpr satcat5::eth::MacAddr satcat5::test::Crosslink::MAC0;
constexpr satcat5::eth::MacAddr satcat5::test::Crosslink::MAC1;
constexpr satcat5::ip::Addr satcat5::test::Crosslink::IP0;
constexpr satcat5::ip::Addr satcat5::test::Crosslink::IP1;

Crosslink::Crosslink()
{
    // Crosslink the two interfaces.
    eth0.connect(&eth1);
    eth1.connect(&eth0);
}

void Crosslink::set_loss_rate(float rate)
{
    eth0.set_loss_rate(rate);
    eth1.set_loss_rate(rate);
}

CrosslinkEth::CrosslinkEth()
    : net0(MAC0, &eth0, &eth0)
    , net1(MAC1, &eth1, &eth1)
{
    // Nothing else to initialize
}

CrosslinkIp::CrosslinkIp()
    : net0(MAC0, IP0, &eth0, &eth0, &clock)
    , net1(MAC1, IP1, &eth1, &eth1, &clock)
{
    // Nothing else to initialize
}
