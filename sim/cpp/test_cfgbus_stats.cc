//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the NetworkStats class

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_stats.h>

class MockStats final : public satcat5::test::MockConfigBusMmap {
public:
    MockStats() {
        refresh_regs(1);    // Set initial state
    }

    void refresh_regs(u32 val) {
        for (u32 a = 0 ; a < satcat5::cfg::REGS_PER_DEVICE ; ++a)
            m_regs[a] = val + a;
    }
};

TEST_CASE("NetworkStats") {
    MockStats* mock = new MockStats();
    satcat5::cfg::NetworkStats uut(mock, 0);

    SECTION("refresh") {
        // Confirm UUT writes to refresh register on demand.
        CHECK(uut.get_port(0).bcast_bytes != 0);
        uut.refresh_now();
        CHECK(uut.get_port(0).bcast_bytes == 0);
    }

    SECTION("port0") {
        // Confirm Port 0 returns the expected initial state.
        satcat5::cfg::TrafficStats stats = uut.get_port(0);
        CHECK(stats.bcast_bytes     == 1);
        CHECK(stats.bcast_frames    == 2);
        CHECK(stats.rcvd_bytes      == 3);
        CHECK(stats.rcvd_frames     == 4);
        CHECK(stats.sent_bytes      == 5);
        CHECK(stats.sent_frames     == 6);
        CHECK(stats.errct_mac       == 0);
        CHECK(stats.errct_ovr_tx    == 0);
        CHECK(stats.errct_ovr_rx    == 0);
        CHECK(stats.errct_pkt       == 7);
        CHECK(stats.errct_ptp_rx    == 0);
        CHECK(stats.errct_ptp_tx    == 8);
        CHECK(stats.status          == 9);
    }

    SECTION("port1") {
        // Confirm Port 1 returns the expected initial state.
        satcat5::cfg::TrafficStats stats = uut.get_port(1);
        CHECK(stats.bcast_bytes     == 17);
        CHECK(stats.bcast_frames    == 18);
        CHECK(stats.rcvd_bytes      == 19);
        CHECK(stats.rcvd_frames     == 20);
        CHECK(stats.sent_bytes      == 21);
        CHECK(stats.sent_frames     == 22);
        CHECK(stats.errct_mac       == 0);
        CHECK(stats.errct_ovr_tx    == 0);
        CHECK(stats.errct_ovr_rx    == 0);
        CHECK(stats.errct_pkt       == 23);
        CHECK(stats.errct_ptp_rx    == 0);
        CHECK(stats.errct_ptp_tx    == 24);
        CHECK(stats.status          == 25);
    }

    SECTION("port999") {
        // Out-of-bounds access should return null object.
        satcat5::cfg::TrafficStats stats = uut.get_port(999);
        CHECK(stats.bcast_bytes     == 0);
        CHECK(stats.bcast_frames    == 0);
        CHECK(stats.rcvd_bytes      == 0);
        CHECK(stats.rcvd_frames     == 0);
        CHECK(stats.sent_bytes      == 0);
        CHECK(stats.sent_frames     == 0);
        CHECK(stats.errct_mac       == 0);
        CHECK(stats.errct_ovr_tx    == 0);
        CHECK(stats.errct_ovr_rx    == 0);
        CHECK(stats.errct_pkt       == 0);
        CHECK(stats.errct_ptp_rx    == 0);
        CHECK(stats.errct_ptp_tx    == 0);
        CHECK(stats.status          == 0);
    }

    delete mock;
}
