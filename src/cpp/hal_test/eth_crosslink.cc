//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_test/eth_crosslink.h>

using satcat5::test::Crosslink;
using satcat5::test::CrosslinkEth;
using satcat5::test::CrosslinkIp;
using satcat5::test::CrosslinkSpp;

// Workaround to ensure C++11 allocates static constants.
// See also: https://stackoverflow.com/questions/8452952/
constexpr satcat5::eth::MacAddr satcat5::test::Crosslink::MAC0;
constexpr satcat5::eth::MacAddr satcat5::test::Crosslink::MAC1;
constexpr satcat5::ip::Addr satcat5::test::Crosslink::IP0;
constexpr satcat5::ip::Addr satcat5::test::Crosslink::IP1;

Crosslink::Crosslink(const char* filename, u16 type)
    : pcap(true)
    , eth0(&pcap)
    , eth1(&pcap)
{
    // Crosslink the two interfaces.
    eth0.connect(&eth1);
    eth1.connect(&eth0);
    // Start the PCAP log.
    pcap.open(satcat5::test::sim_filename(filename, "pcap"), type);
}

void Crosslink::set_loss_rate(float rate) {
    eth0.set_loss_rate(rate);
    eth1.set_loss_rate(rate);
}

void Crosslink::set_zero_pad(unsigned len) {
    eth0.set_zero_pad(len);
    eth1.set_zero_pad(len);
}

CrosslinkEth::CrosslinkEth(const char* filename)
    : Crosslink(filename)
    , net0(MAC0, &eth0, &eth0)
    , net1(MAC1, &eth1, &eth1)
{
    // Nothing else to initialize
}

CrosslinkIp::CrosslinkIp(const char* filename)
    : Crosslink(filename)
    , net0(MAC0, IP0, &eth0, &eth0, &timer)
    , net1(MAC1, IP1, &eth1, &eth1, &timer)
{
    // Nothing else to initialize
}

CrosslinkSpp::CrosslinkSpp(const char* filename)
    : Crosslink(filename, satcat5::io::LINKTYPE_USER0)
    , spp0(&eth0, &eth0)
    , spp1(&eth1, &eth1)
{
    // Nothing else to initialize
}
