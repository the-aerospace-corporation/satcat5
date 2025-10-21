//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for packet combiner

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/pkt_combiner.h>

#define SM_PKT_SIZE 100
#define MD_PKT_SIZE 200
#define LG_PKT_SIZE 300
#define XL_PKT_SIZE 600

TEST_CASE("pkt_combine") {
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;
    satcat5::test::RandomSource ref1(LG_PKT_SIZE),
                                ref2(LG_PKT_SIZE),
                                ref3(LG_PKT_SIZE),
                                ref4(LG_PKT_SIZE),
                                ref5(LG_PKT_SIZE),
                                ref6(LG_PKT_SIZE),
                                ref_sm(SM_PKT_SIZE),
                                ref_empty(0);

    // Create I/O buffers and uut
    satcat5::io::PacketBufferStatic<LG_PKT_SIZE+2> pkt_rx(1);
    satcat5::io::PacketCombinerStatic<8192> uut(&pkt_rx);
    u8 tmp[XL_PKT_SIZE];

    SECTION("combine") {
        // Write 3 small packets
        for (int i = 0; i < 3; i++) {
            ref1.read_bytes(SM_PKT_SIZE, tmp);
            uut.write_bytes(SM_PKT_SIZE, tmp);
            CHECK(uut.write_finalize());
        }

        // Check 3 small packets were combined
        satcat5::poll::service();
        CHECK(satcat5::test::read_equal(ref1.read(), &pkt_rx));

        // Write 1 large packet
        ref2.read_bytes(LG_PKT_SIZE, tmp);
        uut.write_bytes(LG_PKT_SIZE, tmp);
        CHECK(uut.write_finalize());

        // Check 1 large packet is intact
        satcat5::poll::service();
        CHECK(satcat5::test::read_equal(ref2.read(), &pkt_rx));

        // Write 3 medium packets
        // Pkt 1
        ref3.read_bytes(MD_PKT_SIZE, tmp);
        uut.write_bytes(MD_PKT_SIZE, tmp);
        CHECK(uut.write_finalize());
        // Pkt 2
        ref3.read_bytes(SM_PKT_SIZE, tmp);
        ref4.read_bytes(SM_PKT_SIZE, &(tmp[SM_PKT_SIZE]));
        uut.write_bytes(MD_PKT_SIZE, tmp);
        CHECK(uut.write_finalize());
        // Pkt 3
        ref4.read_bytes(MD_PKT_SIZE, tmp);
        uut.write_bytes(MD_PKT_SIZE, tmp);
        CHECK(uut.write_finalize());

        // Check 3 medium packets were combined into 2 full packets
        satcat5::poll::service();
        CHECK(satcat5::test::read_equal(ref3.read(), &pkt_rx));
        satcat5::poll::service();
        CHECK(satcat5::test::read_equal(ref4.read(), &pkt_rx));

        // Write 1 XL packet
        ref5.read_bytes(LG_PKT_SIZE, tmp);
        ref6.read_bytes(LG_PKT_SIZE, &(tmp[LG_PKT_SIZE]));
        uut.write_bytes(XL_PKT_SIZE, tmp);
        CHECK(uut.write_finalize());

        // Check 1 XL packet was split into 2 full packets
        satcat5::poll::service();
        CHECK(satcat5::test::read_equal(ref5.read(), &pkt_rx));
        satcat5::poll::service();
        CHECK(satcat5::test::read_equal(ref6.read(), &pkt_rx));
    }

    SECTION("timeout") {
        // Enable timeout
        uut.set_timeout(1000);

        // Write 1 small packet
        ref_sm.read_bytes(SM_PKT_SIZE, tmp);
        uut.write_bytes(SM_PKT_SIZE, tmp);
        CHECK(uut.write_finalize());

        // Check output is empty before timer event
        timer.sim_wait(500);
        CHECK(satcat5::test::read_equal(ref_empty.read(), &pkt_rx));

        // Check output matches after timer event
        timer.sim_wait(600);
        CHECK(satcat5::test::read_equal(ref_sm.read(), &pkt_rx));

        // Disable timeout
        uut.set_timeout(0);

        // Write 1 small packet
        ref_sm.read_bytes(SM_PKT_SIZE, tmp);
        uut.write_bytes(SM_PKT_SIZE, tmp);
        CHECK(uut.write_finalize());

        // Check output is empty
        timer.sim_wait(500);
        CHECK(satcat5::test::read_equal(ref_empty.read(), &pkt_rx));
        timer.sim_wait(600);
        CHECK(satcat5::test::read_equal(ref_empty.read(), &pkt_rx));
    }
}
