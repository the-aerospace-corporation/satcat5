//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for BufferedIO, BufferedCopy, and BufferedWriter classes.

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/sim_utils.h>
#include <satcat5/io_buffer.h>
#include <satcat5/udp_socket.h>

namespace io = satcat5::io;

// Helper class for testing BufferedIO in loopback mode:
// Immediately forward all Tx data to the Rx buffer.
class BufferedPassthrough : public io::BufferedIO {
public:
    BufferedPassthrough(unsigned nbytes)
        : io::BufferedIO(new u8[nbytes], nbytes, nbytes/64,
                         new u8[nbytes], nbytes, nbytes/64)
    {
        // Nothing else to initialize.
    }
    ~BufferedPassthrough() {
        delete[] m_tx.get_buff_dtor();
        delete[] m_rx.get_buff_dtor();
    }
protected:
    void data_rcvd(satcat5::io::Readable* src) override {
        // Loopback = Copy data from m_tx to m_rx.
        // Note: m_tx = external writes, internal reads
        //       m_rx = external reads, internal writes
        unsigned npeek, ntotal = m_tx.get_read_ready();
        while (npeek = m_tx.get_peek_ready()) {
            const u8* blk = m_tx.peek(npeek);
            REQUIRE(blk != 0);
            m_rx.write_bytes(npeek, blk);
            CHECK(m_tx.read_consume(npeek));
        }
        CHECK(m_rx.get_write_partial() == ntotal);
        CHECK(m_rx.write_finalize());
        m_tx.read_finalize();
    }
};

// Write a short packet.
bool writepkt(io::Writeable* wr) {
    wr->write_u8(12);
    wr->write_u16(1234);
    wr->write_u32(12345678);
    return wr->write_finalize();
}

// Read and check a short packet.
void readpkt(io::Readable* rd) {
    REQUIRE(rd->get_read_ready() == 7);
    CHECK(rd->read_u8() == 12);
    CHECK(rd->read_u16() == 1234);
    CHECK(rd->read_u32() == 12345678);
    rd->read_finalize();
}

TEST_CASE("BufferedIO") {
    SATCAT5_TEST_START;                 // Simulation infrastructure
    BufferedPassthrough uut(1024);      // Unit under test

    // Basic test with a single short packet.
    SECTION("Basic") {
        REQUIRE(writepkt(&uut));
        satcat5::poll::service();
        readpkt(&uut);
    }

    // Write/read a large number of packets.
    SECTION("Full") {
        unsigned pkt = 0;
        while (writepkt(&uut))          // Write packets until full...
            ++pkt;                      // (Count the number written.)
        satcat5::poll::service_all();   // Deliver each one to Rx-buffer.
        for (unsigned a = 0 ; a < pkt ; ++a)
            readpkt(&uut);              // Read and check each packet.
    }

    // Write/read enough for a few laps around the circular buffer.
    SECTION("Interleaved") {
        unsigned pkt = 0;
        while (writepkt(&uut))          // Write packet until full...
            ++pkt;                      // (Count the number written.)
        REQUIRE(pkt > 3);               // (Sanity check on packet count.)
        satcat5::poll::service_all();   // Deliver each one to Rx-buffer.
        for (unsigned a = 0 ; a < 20 ; ++a) {
            for (unsigned a = 0 ; a < pkt/3 ; ++a)
                readpkt(&uut);              // Read the first few packets.
            for (unsigned a = 0 ; a < pkt/3 ; ++a)
                CHECK(writepkt(&uut));      // Write some new packets.
            satcat5::poll::service_all();   // Deliver the new packets.
        }
        for (unsigned a = 0 ; a < pkt ; ++a)
            readpkt(&uut);              // Read all remaining packets.
    }
}

TEST_CASE("BufferedCopy") {
    SATCAT5_TEST_START;                 // Simulation infrastructure

    SECTION("Packet") {
        io::PacketBufferHeap tx, rx;
        io::BufferedCopy uut(&tx, &rx, io::CopyMode::PACKET);
        CHECK(uut.src() == &tx);
        CHECK(uut.dst() == &rx);
        tx.write_u8(12);
        tx.write_u16(1234);
        tx.write_u32(12345678);
        REQUIRE(tx.write_finalize());
        satcat5::poll::service();
        CHECK(rx.read_u8() == 12);
        CHECK(rx.read_u16() == 1234);
        CHECK(rx.read_u32() == 12345678);
        rx.read_finalize();
    }

    SECTION("Stream") {
        io::StreamBufferHeap tx(32), rx(16);
        io::BufferedCopy uut(&tx, &rx, io::CopyMode::STREAM);
        tx.write_str("Long test message in two parts.");
        REQUIRE(tx.write_finalize());
        satcat5::poll::service();
        CHECK(satcat5::test::read(&rx, "Long test messag"));
        satcat5::poll::service();
        CHECK(satcat5::test::read(&rx, "e in two parts."));
    }
}

TEST_CASE("BufferedStream") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Back-to-back test network.
    constexpr satcat5::udp::Port TEST_PORT = {0x4321};
    satcat5::test::CrosslinkIp xlink(__FILE__);
    satcat5::udp::Address send(&xlink.net0.m_udp);
    satcat5::udp::Socket recv(&xlink.net1.m_udp);
    send.connect(xlink.IP1, TEST_PORT);
    recv.bind(TEST_PORT);

    // Unit under test with chunk-size = 8 bytes.
    io::StreamBufferHeap tx;
    io::BufferedStream uut(&tx, &send, 8);

    SECTION("Exact") {
        // Exact multiples only, first segment should stall.
        uut.set_timeout(0);
        CHECK(satcat5::test::write(&tx, "7 bytes"));
        xlink.timer.sim_wait(1000);
        CHECK(recv.get_read_ready() == 0);
        // With more data, it should send two packets.
        CHECK(satcat5::test::write(&tx, "9 more..."));
        xlink.timer.sim_wait(1000);
        CHECK(satcat5::test::read(&recv, "7 bytes9"));
        CHECK(satcat5::test::read(&recv, " more..."));
    }

    SECTION("Split") {
        // Normal mode should send after timeout.
        uut.set_timeout(10);
        CHECK(satcat5::test::write(&tx, "7 bytes"));
        xlink.timer.sim_wait(1000);
        CHECK(satcat5::test::read(&recv, "7 bytes"));
        // A longer message will be split into two parts.
        CHECK(satcat5::test::write(&tx, "9 more..."));
        xlink.timer.sim_wait(1000);
        CHECK(satcat5::test::read(&recv, "9 more.."));
        CHECK(satcat5::test::read(&recv, "."));
    }
}

TEST_CASE("BufferedTee") {
    SATCAT5_TEST_START;                 // Simulation infrastructure
    io::BufferedTee uut;                // Unit under test
    io::PacketBufferHeap rx1, rx2, rx3; // Working buffers

    // Written data should be copied to all outputs.
    SECTION("Basic") {
        const std::string TEST1("Test message 1.");
        const std::string TEST2("Test message 2 is longer.");
        // Copy to all three outputs.
        uut.add(&rx1);
        uut.add(&rx2);
        uut.add(&rx3);
        REQUIRE(satcat5::test::write(&uut, TEST1));
        CHECK(satcat5::test::read(&rx1, TEST1));
        CHECK(satcat5::test::read(&rx2, TEST1));
        CHECK(satcat5::test::read(&rx3, TEST1));
        // Remove the middle output and try again.
        uut.remove(&rx2);
        REQUIRE(satcat5::test::write(&uut, TEST2));
        CHECK(satcat5::test::read(&rx1, TEST2));
        CHECK(rx2.get_read_ready() == 0);
        CHECK(satcat5::test::read(&rx3, TEST2));
    }
}

TEST_CASE("BufferedWriter") {
    SATCAT5_TEST_START;                 // Simulation infrastructure
    io::PacketBufferHeap rx;            // Final destination
    io::BufferedWriterHeap uut(&rx);    // UUT copies data to rx

    SECTION("Basic") {
        uut.write_u8(12);
        uut.write_u16(1234);
        uut.write_u32(12345678);
        REQUIRE(uut.write_finalize());
        satcat5::poll::service();
        CHECK(rx.read_u8() == 12);
        CHECK(rx.read_u16() == 1234);
        CHECK(rx.read_u32() == 12345678);
        rx.read_finalize();
    }
}
