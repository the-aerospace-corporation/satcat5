//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Unit of the "MuxDown" and "MuxUp" multiplexers

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/io_multiplexer.h>

using satcat5::io::BufferedCopy;
using satcat5::io::MuxDownStatic;
using satcat5::io::MuxUpStatic;
using satcat5::io::PacketBufferHeap;

TEST_CASE("MuxDown") {
    SATCAT5_TEST_START; // Simulation infrastructure

    // Create the downstream port and the unit under test.
    // (MuxDown = One port, many controllers.)
    PacketBufferHeap ptx, prx, rx0, rx1;
    MuxDownStatic<2> uut(&prx, &ptx);

    // Link each of the upstream controllers.
    BufferedCopy cp0(uut.port_rd(0), &rx0);
    BufferedCopy cp1(uut.port_rd(1), &rx1);

    // Send messages from the port to each controller.
    SECTION("port_rx") {
        uut.select(0);
        CHECK(satcat5::test::write(&prx, "Message to Port 0."));
        satcat5::poll::service_all();
        uut.select(1);
        CHECK(satcat5::test::write(&prx, "Message to Port 1."));
        satcat5::poll::service_all();
        uut.select(2);
        CHECK(satcat5::test::write(&prx, "Message to Port 2."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&rx0, "Message to Port 0."));
        CHECK(satcat5::test::read(&rx1, "Message to Port 1."));
    }

    // Send messages from each controller to the port.
    SECTION("port_tx") {
        uut.select(0);
        CHECK(satcat5::test::write(uut.port_wr(0), "Message 0.0"));
        CHECK(satcat5::test::write(uut.port_wr(1), "Message 0.1"));
        satcat5::poll::service_all();
        uut.select(1);
        CHECK(satcat5::test::write(uut.port_wr(0), "Message 1.0"));
        CHECK(satcat5::test::write(uut.port_wr(1), "Message 1.1"));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&ptx, "Message 0.0"));
        CHECK(satcat5::test::read(&ptx, "Message 1.1"));
    }
}

TEST_CASE("MuxUp") {
    SATCAT5_TEST_START; // Simulation infrastructure
    satcat5::test::IoEventCounter event;

    // Create the unit under test and a control buffer.
    // (MuxUp = One controller, many ports.)
    MuxUpStatic<2> uut;
    uut.set_callback(&event);

    // Link each of the downstream ports.
    // Note: These will be destroyed *before* uut, which would cause
    //  a race condition if we didn't have the data_unlink() API.
    PacketBufferHeap rx0, rx1, tx0, tx1;
    uut.port_set(0, &rx0, &tx0);
    uut.port_set(1, &rx1, &tx1);

    // Send messages to a nonexistent port.

    // Send messages from the controller to each port.
    SECTION("port_rx") {
        uut.select(0);
        CHECK(satcat5::test::write(&rx0, "Message 0.0"));
        CHECK(satcat5::test::write(&rx1, "Message 0.1"));
        CHECK(event.count() == 0);
        satcat5::poll::service();
        CHECK(satcat5::test::read(&uut, "Message 0.0"));
        CHECK(event.count() == 1);
        uut.select(1);
        CHECK(satcat5::test::write(&rx0, "Message 1.0"));
        CHECK(satcat5::test::write(&rx1, "Message 1.1"));
        satcat5::poll::service();
        CHECK(satcat5::test::read(&uut, "Message 1.1"));
        CHECK(event.count() == 2);
        uut.select(2);
        CHECK(satcat5::test::write(&rx0, "Message 2.0"));
        CHECK(satcat5::test::write(&rx1, "Message 2.1"));
        satcat5::poll::service();
        CHECK(uut.get_read_ready() == 0);
        CHECK(event.count() == 2);
    }

    // Send messages to the controller from each port.
    SECTION("port_tx") {
        uut.select(0);
        CHECK(satcat5::test::write(&uut, "Message to Port 0."));
        satcat5::poll::service_all();
        uut.select(1);
        CHECK(satcat5::test::write(&uut, "Message to Port 1."));
        satcat5::poll::service_all();
        uut.select(2);
        CHECK(satcat5::test::write(&uut, "Message to Port 2."));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&tx0, "Message to Port 0."));
        CHECK(satcat5::test::read(&tx1, "Message to Port 1."));
        CHECK(event.count() == 0);
    }
}
