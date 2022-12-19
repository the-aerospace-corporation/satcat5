//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation
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
// Test cases for the ConfigBus PTP reference timer

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_ptpref.h>

// Constants relating to the unit under test:
static const unsigned PTP_DEVADDR = 42;
static const unsigned PTP_REGADDR = 43;

TEST_CASE("cfgbus_ptpref") {
    // PRNG for these tests.
    Catch::SimplePcg32 rng;

    // Instantiate simulated register map.
    satcat5::test::CfgDevice cfg;
    cfg[PTP_REGADDR].read_default_echo();

    // Unit under test.
    satcat5::cfg::PtpReference uut(&cfg, PTP_DEVADDR, PTP_REGADDR);

    SECTION("random") {
        // Write a random value, should read same value.
        for (unsigned a = 0 ; a < 20 ; ++a) {
            s32 val = (s32)rng();
            uut.set(val);
            CHECK(uut.get() == val);
        }
    }
}
