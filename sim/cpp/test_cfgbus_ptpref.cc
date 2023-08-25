//////////////////////////////////////////////////////////////////////////
// Copyright 2022, 2023 The Aerospace Corporation
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

using satcat5::cfg::ptpref_scale;
using satcat5::cfg::PtpRealtime;
using satcat5::cfg::PtpReference;
using satcat5::ptp::Time;

// Constants relating to the unit under test:
static const unsigned PTP_DEVADDR = 42;
static const unsigned PTP_REGADDR = 43;

TEST_CASE("cfgbus_ptpref") {
    // PTP time used for testing.
    const Time REF_TIME(0xDEADBEEFCAFEull, 0x7654321, 0x4242);
    const Time REF_ZERO(0);

    // Instantiate simulated register map.
    satcat5::test::CfgDevice cfg;
    cfg[PTP_REGADDR+0].read_default_echo();
    cfg[PTP_REGADDR+1].read_default_echo();
    cfg[PTP_REGADDR+2].read_default_echo();
    cfg[PTP_REGADDR+3].read_default_echo();
    cfg[PTP_REGADDR+4].read_default_echo();
    cfg[PTP_REGADDR+5].read_default_echo();

    SECTION("scale") {
        CHECK(ptpref_scale(125e6) > ptpref_scale(10e6));
    }

    SECTION("PtpReference") {
        PtpReference uut(&cfg, PTP_DEVADDR, PTP_REGADDR);
        // Coarse adjustment has no effect.
        CHECK(uut.clock_adjust(REF_TIME) == REF_TIME);
        CHECK(cfg[PTP_REGADDR].read_count() == 0);
        CHECK(cfg[PTP_REGADDR].write_count() == 0);
        // Check the fine-adjust function.
        uut.clock_rate(0x123456789ABCDEFll);
        CHECK(cfg[PTP_REGADDR].write_pop() == 0x01234567u);
        CHECK(cfg[PTP_REGADDR].write_pop() == 0x89ABCDEFu);
        CHECK(cfg[PTP_REGADDR].read_count() == 1);
    }

    SECTION("PtpRealtime") {
        PtpRealtime uut(&cfg, PTP_DEVADDR, PTP_REGADDR);
        // Set followed by get should read the same time.
        CHECK(uut.clock_now() == REF_ZERO);
        CHECK(cfg[PTP_REGADDR+4].write_pop() == 1);
        uut.clock_set(REF_TIME);
        CHECK(cfg[PTP_REGADDR+4].write_pop() == 2);
        CHECK(uut.clock_now() == REF_TIME);
        CHECK(cfg[PTP_REGADDR+4].write_pop() == 1);
        // Coarse adjustment.
        CHECK(uut.clock_adjust(REF_TIME) == Time(0));
        CHECK(cfg[PTP_REGADDR+0].write_pop() == 0x0000DEADu);
        CHECK(cfg[PTP_REGADDR+1].write_pop() == 0xBEEFCAFEu);
        CHECK(cfg[PTP_REGADDR+2].write_pop() == 0x07654321u);
        CHECK(cfg[PTP_REGADDR+3].write_pop() == 0x4242);
        CHECK(cfg[PTP_REGADDR+4].write_pop() == 4);
        // Check the fine-adjust function.
        uut.clock_rate(0x123456789ABCDEFll);
        CHECK(cfg[PTP_REGADDR+5].write_pop() == 0x01234567u);
        CHECK(cfg[PTP_REGADDR+5].write_pop() == 0x89ABCDEFu);
        CHECK(cfg[PTP_REGADDR+5].read_count() == 1);
    }
}
