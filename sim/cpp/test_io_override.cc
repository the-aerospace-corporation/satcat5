//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for remote-control I/O device override

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/io_buffer.h>
#include <satcat5/io_override.h>

using satcat5::io::CopyMode;

TEST_CASE("io_override") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::test::TimerSimulation timer;
    satcat5::test::RandomSource ref1(123), ref2(234);

    SECTION("packet") {
        // Create I/O buffers and connect the unit under test.
        satcat5::io::PacketBufferHeap dev_rx, ovr_rx;
        satcat5::io::PacketBufferHeap dev_tx, ovr_tx;
        satcat5::io::Override uut(&dev_tx, &dev_rx, CopyMode::PACKET);
        uut.set_remote(&ovr_rx, &ovr_tx);
        // Send some data in local mode.
        CHECK(ref1.read()->copy_and_finalize(&uut));
        CHECK(ref2.read()->copy_and_finalize(&uut));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read_equal(ref1.read(), &dev_tx));
        CHECK(satcat5::test::read_equal(ref2.read(), &dev_tx));
        // Receive some data in local mode.
        CHECK(ref1.read()->copy_and_finalize(&dev_rx));
        CHECK(ref2.read()->copy_and_finalize(&dev_rx));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read_equal(ref1.read(), &uut));
        CHECK(satcat5::test::read_equal(ref2.read(), &uut));
        // Send some data in remote mode.
        CHECK(ref1.read()->copy_and_finalize(&ovr_tx));
        CHECK(ref2.read()->copy_and_finalize(&ovr_tx));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read_equal(ref1.read(), &dev_tx));
        CHECK(satcat5::test::read_equal(ref2.read(), &dev_tx));
        // Receive some data in remote mode.
        CHECK(ref1.read()->copy_and_finalize(&dev_rx));
        CHECK(ref2.read()->copy_and_finalize(&dev_rx));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read_equal(ref1.read(), &ovr_rx));
        CHECK(satcat5::test::read_equal(ref2.read(), &ovr_rx));
    }

    SECTION("stream") {
        // Create I/O buffers and connect the unit under test.
        auto dev_rx = new satcat5::io::StreamBufferHeap;
        auto lcl_rx = new satcat5::io::StreamBufferHeap;
        satcat5::io::Override uut(nullptr, dev_rx, CopyMode::STREAM);
        satcat5::io::BufferedCopy cpy(&uut, lcl_rx, CopyMode::STREAM);
        // Received data should be copied to the local buffer.
        CHECK(ref1.read()->copy_and_finalize(dev_rx));
        CHECK(ref2.read()->copy_and_finalize(dev_rx));
        satcat5::poll::service_all();
        CHECK(lcl_rx->get_read_ready() == ref1.len() + ref2.len());
        // Delete these first, so we can test setup/teardown edge cases.
        delete dev_rx;
        delete lcl_rx;
    }

    SECTION("timeout") {
        // Create I/O buffers and connect the unit under test.
        satcat5::io::StreamBufferHeap dev_rx, dev_tx;
        satcat5::io::Override uut(&dev_tx, &dev_rx, CopyMode::STREAM);
        // Check that the blocks reverts to local mode after the timeout.
        uut.set_timeout(1000);
        CHECK_FALSE(uut.is_remote());   // Default is local mode
        uut.set_override(true);
        CHECK(uut.is_remote());         // Force into remote mode
        timer.sim_wait(2000);
        CHECK_FALSE(uut.is_remote());   // Revert to local mode
    }
}
