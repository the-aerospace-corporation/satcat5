//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for UDP keep-alive messages

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/udp_keep_alive.h>

TEST_CASE("udp_keep_alive") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Network communication infrastructure.
    satcat5::test::CrosslinkIp xlink(__FILE__);

    // Unit under test at each end of network link.
    satcat5::udp::KeepAlive uut0(&xlink.net0.m_udp, 1234, "UUT0");
    satcat5::udp::KeepAlive uut1(&xlink.net1.m_udp, 1234, "UUT1");

    SECTION("broadcast") {
        uut0.timer_every(100);
        xlink.timer.sim_wait(1000);
    }

    SECTION("unicast") {
        uut0.connect(xlink.IP1);
        uut0.timer_every(100);
        xlink.timer.sim_wait(1000);
    }
}
