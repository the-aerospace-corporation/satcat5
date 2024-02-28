//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the SatCat5 "Switch Telemetry" class

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_stats.h>
#include <satcat5/switch_cfg.h>
#include <satcat5/switch_telemetry.h>

TEST_CASE("switch_telemetry") {
    // Test infrastructure.
    satcat5::log::ToConsole logger;
    satcat5::test::TimerAlways timekeeper;
    satcat5::test::CrosslinkIp xlink;

    // Mock interface for the SwitchConfig object.
    satcat5::test::CfgDevice reg_cfg;
    reg_cfg.read_default(7);
    
    // Mock interface for the NetworkStats object.
    satcat5::test::CfgDevice reg_stats;
    reg_stats.read_default(0);

    // Unit under test.
    satcat5::udp::Telemetry tlm(&xlink.net0.m_udp, satcat5::udp::PORT_CBOR_TLM);
    satcat5::eth::SwitchConfig cfg(&reg_cfg, 0);
    satcat5::cfg::NetworkStats stats(&reg_stats, 0);
    satcat5::udp::Socket rx_udp(&xlink.net1.m_udp);
    rx_udp.bind(satcat5::udp::PORT_CBOR_TLM);

    // Basic test with SwitchConfig only.
    SECTION("basic1") {
        satcat5::eth::SwitchTelemetry uut(&tlm, &cfg, 0);
        timekeeper.sim_wait(60000); // 60 seconds = two full rounds.
        CHECK(rx_udp.get_read_ready() > 0);
    }

    // Basic test with SwitchConfig and NetworkStats.
    SECTION("basic2") {
        satcat5::eth::SwitchTelemetry uut(&tlm, &cfg, &stats);
        timekeeper.sim_wait(60000); // 60 seconds = two full rounds.
        CHECK(rx_udp.get_read_ready() > 0);
    }
}
