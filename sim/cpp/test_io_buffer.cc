//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for BufferedIO, BufferedCopy, and BufferedWriter classes.

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/io_buffer.h>

namespace io    = satcat5::io;

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
    void data_rcvd() override {
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
    io::PacketBufferHeap tx, rx;        // Test buffers
    io::BufferedCopy uut(&tx, &rx);     // UUT copies from tx to rx

    SECTION("Basic") {
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
}

TEST_CASE("BufferedWriter") {
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
