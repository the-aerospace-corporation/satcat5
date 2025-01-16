//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus PTP reference timer

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_ptpref.h>

using satcat5::cfg::PtpRealtime;
using satcat5::cfg::PtpReference;
using satcat5::ptp::Time;
using satcat5::ptp::TIME_ZERO;

// Constants relating to the unit under test:
static const unsigned PTP_DEVADDR = 42;
static const unsigned PTP_REGADDR = 43;
static const u32 OP_READ    = 0x01000000u;
static const u32 OP_WRITE   = 0x02000000u;
static const u32 OP_INCR    = 0x04000000u;

TEST_CASE("cfgbus_ptpref") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // PTP time used for testing.
    const Time REF_TIME(0xDEADBEEFCAFEull, 0x7654321, 0x4242);

    // Instantiate simulated register map.
    satcat5::test::CfgDevice cfg;
    cfg[PTP_REGADDR+0].read_default_echo();
    cfg[PTP_REGADDR+1].read_default_echo();
    cfg[PTP_REGADDR+2].read_default_echo();
    cfg[PTP_REGADDR+3].read_default_echo();
    cfg[PTP_REGADDR+4].read_default_echo();
    cfg[PTP_REGADDR+5].read_default_echo();
    auto reg = cfg.get_register(PTP_DEVADDR, PTP_REGADDR);

    SECTION("PtpReference") {
        PtpReference uut(reg, 125e6);
        // Coarse adjustment has no effect.
        CHECK(uut.clock_adjust(REF_TIME) == REF_TIME);
        CHECK(cfg[PTP_REGADDR].read_count() == 0);
        CHECK(cfg[PTP_REGADDR].write_count() == 0);
        // Readout of current time is not supported.
        CHECK(uut.clock_now() == TIME_ZERO);
        // Check the raw fine-adjust function.
        uut.clock_rate_raw(0x123456789ABCDEFll);
        CHECK(cfg[PTP_REGADDR].write_pop() == 0x01234567u);
        CHECK(cfg[PTP_REGADDR].write_pop() == 0x89ABCDEFu);
        CHECK(cfg[PTP_REGADDR].read_count() == 1);
        // Check the scaled fine-adjust function.
        uut.clock_rate(0x123456789ll);
        CHECK(cfg[PTP_REGADDR].write_count() == 4);
        CHECK(cfg[PTP_REGADDR].read_count() == 2);
    }

    SECTION("PtpRealtime") {
        PtpRealtime uut(reg, 125e6);
        // Set followed by get should read the same time.
        CHECK(uut.clock_now() == TIME_ZERO);
        CHECK(cfg[PTP_REGADDR+4].write_pop() == OP_READ);
        uut.clock_set(REF_TIME);
        CHECK(cfg[PTP_REGADDR+4].write_pop() == OP_WRITE);
        CHECK(uut.clock_now() == REF_TIME);
        CHECK(cfg[PTP_REGADDR+4].write_pop() == OP_READ);
        // Coarse adjustment.
        CHECK(uut.clock_adjust(REF_TIME) == Time(0));
        CHECK(cfg[PTP_REGADDR+0].write_pop() == 0x0000DEADu);
        CHECK(cfg[PTP_REGADDR+1].write_pop() == 0xBEEFCAFEu);
        CHECK(cfg[PTP_REGADDR+2].write_pop() == 0x07654321u);
        CHECK(cfg[PTP_REGADDR+3].write_pop() == 0x4242);
        CHECK(cfg[PTP_REGADDR+4].write_pop() == OP_INCR);
        // Check the raw fine-adjust function.
        uut.clock_rate_raw(0x123456789ABCDEFll);
        CHECK(cfg[PTP_REGADDR+5].write_pop() == 0x01234567u);
        CHECK(cfg[PTP_REGADDR+5].write_pop() == 0x89ABCDEFu);
        CHECK(cfg[PTP_REGADDR+5].read_count() == 1);
        // Check the scaled fine-adjust function.
        uut.clock_rate(0x123456789ll);
        CHECK(cfg[PTP_REGADDR+5].write_count() == 4);
        CHECK(cfg[PTP_REGADDR+5].read_count() == 2);
    }
}
