//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// Test cases for the NetworkStats class

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_stats.h>

class MockStats : public satcat5::test::MockConfigBusMmap {
public:
    MockStats() {
        refresh_regs(0);    // Clear initial state
    }

    void refresh_regs(u32 val) {
        for (u32 a = 0 ; a < satcat5::cfg::REGS_PER_DEVICE ; ++a)
            m_regs[a] = val + a;
    }
};

TEST_CASE("NetworkStats") {
    MockStats mock;
    satcat5::cfg::NetworkStats uut(&mock, 0);

    SECTION("refresh") {
        // Confirm UUT writes to refresh register on demand.
        CHECK(uut.get_port(0)->status != 0);
        uut.refresh_now();
        CHECK(uut.get_port(0)->status == 0);
    }

    SECTION("port1") {
        // Confirm Port 1 returns the expected initial state.
        volatile satcat5::cfg::TrafficStats* stats = uut.get_port(1);
        CHECK(stats->bcast_bytes    == 8);
        CHECK(stats->bcast_frames   == 9);
        CHECK(stats->rcvd_bytes     == 10);
        CHECK(stats->rcvd_frames    == 11);
        CHECK(stats->sent_bytes     == 12);
        CHECK(stats->sent_frames    == 13);
        CHECK(stats->errct_mac      == 14);
        CHECK(stats->errct_ovr_tx   == 0);
        CHECK(stats->errct_ovr_rx   == 0);
        CHECK(stats->errct_pkt      == 0);
        CHECK(stats->status         == 15);
    }

    SECTION("port999") {
        // Out-of-bounds access should return null pointer.
        CHECK(uut.get_port(999) == 0);
    }
}
