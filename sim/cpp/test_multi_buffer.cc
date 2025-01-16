//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the multi-source / multi-sink packet buffer

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <list>
#include <satcat5/multi_buffer.h>

using satcat5::io::LimitedRead;
using satcat5::io::MultiBuffer;
using satcat5::io::MultiPacket;
using satcat5::io::MultiReaderPriority;
using satcat5::io::MultiReaderSimple;
using satcat5::io::MultiWriter;
using satcat5::io::Readable;
using satcat5::io::Writeable;
using satcat5::test::RandomSource;
using satcat5::test::write_random_bytes;

static constexpr bool VERBOSE = false;

static bool compare_read_bytes(Readable* ref, Readable* uut) {
    // Sanity check on packet length.
    unsigned ref_len = ref->get_read_ready();
    if (ref_len == 0) return (uut->get_read_ready() == 0);
    if (VERBOSE) printf("%u vs %u\n", ref_len, uut->get_read_ready());
    if (ref_len > SATCAT5_MBUFF_PKTLEN) return false;
    // Copy from unit under test to a temporary buffer.
    u8 temp[SATCAT5_MBUFF_PKTLEN];
    if (!uut->read_bytes(ref_len, temp)) return false;
    uut->read_finalize();
    // Compare buffer contents against the reference.
    satcat5::io::ArrayRead rd(temp, ref_len);
    return satcat5::test::read_equal(ref, &rd);
}

static void carbon_copy(u8 param, Writeable* ref, MultiWriter* uut) {
    static unsigned pkt_ctr = 0;
    unsigned prev_len = uut->get_write_partial();
    if (param < 192) {
        // Write a few randomized bytes to both objects.
        // Note: Use "write_bytes" here rather than "copy_to", to ensure
        //  all data is copied and confirm overflow handling is correct.
        RandomSource tmp(param + 1);
        if (VERBOSE) printf("write %u + %u\n", prev_len, tmp.len());
        ref->write_bytes(tmp.len(), tmp.raw());
        uut->write_bytes(tmp.len(), tmp.raw());
    } else if (param < 200) {
        // Abort both packets in progress.
        if (VERBOSE) printf("abort\n");
        ref->write_abort();
        uut->write_abort();
    } else if (uut->write_finalize()) {
        // Mirror successful write to unit under test.
        if (VERBOSE) printf("commit %u / %u\n", ++pkt_ctr, prev_len);
        REQUIRE(ref->write_finalize());
    } else {
        // Mirror failed write to unit under test.
        if (VERBOSE) printf("failed\n");
        ref->write_abort();
    }
}

// Reference implementation of an order-preserving priority queue.
class RefQueue {
public:
    struct Item {u16 priority; u32 index;};

    RefQueue() : m_index(0), m_queue() {}

    void debug() const {
        for (auto a = m_queue.begin() ; a != m_queue.end() ; ++a) {
            printf("(%u, %u), ", a->priority, a->index);
        }
        printf("\n");
    }

    u32 index() const {return m_index;}

    u32 pop() {
        // Always pop from head of queue, unless it is empty.
        if (m_queue.empty()) return 0;
        u32 result = m_queue.front().index;
        m_queue.pop_front();
        return result;
    }

    void push(u16 priority) {
        Item item = { priority, m_index++ };
        // Scan from start of queue:
        //  * Always skip the first element. This item has already
        //    been preloaded by the MultiReader and cannot be altered.
        //  * Compare new priority to each subseqent packet. Stop at the
        //    end of the queue of the first packet with lower priority.
        // Note: Insert places the new element just BEFORE the iterator.
        if (priority > 0) {
            if (VERBOSE) debug();
            for (auto a = m_queue.begin() ; a != m_queue.end() ; ++a) {
                if (a == m_queue.begin()) continue;
                if (a->priority >= priority) continue;
                m_queue.insert(a, item); return;
            }
        }
        // Otherwise, insert the new packet at the end of the queue.
        m_queue.push_back(item);
    }

private:
    u32 m_index;
    std::list<Item> m_queue;
};

TEST_CASE("MultiBuffer") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Primary buffer with two read ports and three write ports.
    // Note: Messages are always broadcast to each attached port.
    u8 raw_buff[16384];
    MultiBuffer mbuff(raw_buff, sizeof(raw_buff));
    MultiReaderSimple rd1(&mbuff), rd2(&mbuff);
    MultiWriter wr1(&mbuff), wr2(&mbuff), wr3(&mbuff);

    // Note initial buffer capacity for later reference.
    // (Some overhead is required for the linked-list pointers, etc.)
    const unsigned capacity = mbuff.get_free_bytes();
    REQUIRE(mbuff.consistency());

    // Generate some random data for test packets.
    RandomSource rand1(123);    auto pkt1 = rand1.read();
    RandomSource rand2(234);    auto pkt2 = rand2.read();
    RandomSource rand3(345);    auto pkt3 = rand3.read();
    RandomSource rand4(456);    auto pkt4 = rand4.read();
    RandomSource rand5(567);    auto pkt5 = rand5.read();

    // A fixed test with interleaved partial writes.
    SECTION("interleaved_fixed") {
        // Each packet is split into multiple parts for writing...
        LimitedRead(pkt2, 56).copy_to(&wr1);   // Copy first N bytes
        LimitedRead(pkt1, 60).copy_to(&wr2);
        LimitedRead(pkt3, 99).copy_to(&wr3);
        CHECK(pkt1->copy_and_finalize(&wr2));  // Copy remaining bytes
        LimitedRead(pkt4, 11).copy_to(&wr2);
        CHECK(pkt2->copy_and_finalize(&wr1));
        LimitedRead(pkt4, 11).copy_to(&wr2);
        LimitedRead(pkt5, 42).copy_to(&wr1);
        CHECK(pkt3->copy_and_finalize(&wr3));
        CHECK(pkt4->copy_and_finalize(&wr2));
        CHECK(pkt5->copy_and_finalize(&wr1));
        satcat5::poll::service_all();
        // Confirm read contents on port 1.
        CHECK(satcat5::test::read_equal(&rd1, pkt1));
        CHECK(satcat5::test::read_equal(&rd1, pkt2));
        CHECK(satcat5::test::read_equal(&rd1, pkt3));
        CHECK(satcat5::test::read_equal(&rd1, pkt4));
        CHECK(satcat5::test::read_equal(&rd1, pkt5));
        CHECK(rd1.get_read_ready() == 0);
        // Confirm we haven't prematurely freed any buffers.
        CHECK(mbuff.get_free_bytes() < capacity);
        // Confirm read contents on port 2.
        CHECK(satcat5::test::read_equal(&rd2, pkt1));
        CHECK(satcat5::test::read_equal(&rd2, pkt2));
        CHECK(satcat5::test::read_equal(&rd2, pkt3));
        CHECK(satcat5::test::read_equal(&rd2, pkt4));
        CHECK(satcat5::test::read_equal(&rd2, pkt5));
        CHECK(rd2.get_read_ready() == 0);
        // Buffers should now be freed.
        CHECK(mbuff.get_free_bytes() == capacity);
    }

    // A randomized test with interleaved partial writes.
    SECTION("interleaved_random") {
        // Test against port 1 only, disabling the other port.
        rd2.set_port_enable(false);
        // Packet buffers model the expected state of each port.
        satcat5::io::PacketBufferHeap ref_wr1(2*capacity);
        satcat5::io::PacketBufferHeap ref_wr2(2*capacity);
        satcat5::io::PacketBufferHeap ref_wr3(2*capacity);
        satcat5::io::PacketBufferHeap ref_rd1(2*capacity);
        // Execute a long series of random actions...
        unsigned pkt_ctr = 0;
        for (unsigned a = 0 ; a < 10000 ; ++a) {
            // Randomly read or write units under test.
            u8 action = satcat5::test::rand_u8();
            u8 param  = satcat5::test::rand_u8();
            if (action < 47) {          // Read next packet, if any
                unsigned tmp = ref_rd1.get_read_ready() ? ++pkt_ctr : 0;
                if (VERBOSE) printf("test? %u\n", tmp);
                REQUIRE(compare_read_bytes(&ref_rd1, &rd1));
            } else if (action < 128) {  // Write data to port 1
                carbon_copy(param, &ref_wr1, &wr1);
            } else if (action < 192) {  // Write data to port 2
                carbon_copy(param, &ref_wr2, &wr2);
            } else {                    // Write data to port 3
                carbon_copy(param, &ref_wr3, &wr3);
            }
            // Move any complete reference packets to the output.
            if (ref_wr1.get_read_ready()) ref_wr1.copy_and_finalize(&ref_rd1);
            if (ref_wr2.get_read_ready()) ref_wr2.copy_and_finalize(&ref_rd1);
            if (ref_wr3.get_read_ready()) ref_wr3.copy_and_finalize(&ref_rd1);
            // Deliver packets to each output.
            satcat5::poll::service_all();
        }
        // Check all remaining received packets.
        while (ref_rd1.get_read_ready())
            CHECK(compare_read_bytes(&ref_rd1, &rd1));
        CHECK(rd1.get_read_ready() == 0);
    }

    // Check the contents of several packets using read_bytes().
    SECTION("read_bytes") {
        // Write a few test packets.
        CHECK(pkt1->copy_and_finalize(&wr1));
        CHECK(pkt2->copy_and_finalize(&wr2));
        CHECK(pkt3->copy_and_finalize(&wr1));
        CHECK(pkt4->copy_and_finalize(&wr2));
        CHECK(pkt5->copy_and_finalize(&wr1));
        satcat5::poll::service_all();
        // Compare each output to its reference using a helper function,
        // in contrast to "test::read_equal" using read_u8().
        CHECK(compare_read_bytes(pkt1, &rd1));
        CHECK(compare_read_bytes(pkt1, &rd2));
        CHECK(compare_read_bytes(pkt2, &rd1));
        CHECK(compare_read_bytes(pkt2, &rd2));
        CHECK(compare_read_bytes(pkt3, &rd1));
        CHECK(compare_read_bytes(pkt3, &rd2));
        CHECK(compare_read_bytes(pkt4, &rd1));
        CHECK(compare_read_bytes(pkt4, &rd2));
        CHECK(compare_read_bytes(pkt5, &rd1));
        CHECK(compare_read_bytes(pkt5, &rd2));
    }

    // Check that read_consume() skips ahead as expected.
    SECTION("read_consume") {
        // Disable unused ports for this test.
        rd2.set_port_enable(false);
        // Write a few test packets.
        CHECK(pkt1->copy_and_finalize(&wr1));
        CHECK(pkt2->copy_and_finalize(&wr2));
        CHECK(pkt3->copy_and_finalize(&wr1));
        CHECK(pkt4->copy_and_finalize(&wr2));
        CHECK(pkt5->copy_and_finalize(&wr1));
        satcat5::poll::service_all();
        // For each packet, skip ahead the same amount in the reference
        // and the read-port before comparing the remainder.
        CHECK(pkt1->read_consume(42));
        CHECK(rd1.read_consume(42));
        CHECK(compare_read_bytes(pkt1, &rd1));
        CHECK(pkt2->read_consume(56));
        CHECK(rd1.read_consume(56));
        CHECK(compare_read_bytes(pkt2, &rd1));
        CHECK(pkt3->read_consume(60));
        CHECK(rd1.read_consume(60));
        CHECK(compare_read_bytes(pkt3, &rd1));
        CHECK(pkt4->read_consume(99));
        CHECK(rd1.read_consume(99));
        CHECK(compare_read_bytes(pkt4, &rd1));
        // Confirm that excessive skip-ahead is rejected.
        CHECK_FALSE(pkt5->read_consume(9999));
        CHECK_FALSE(rd1.read_consume(9999));
        // Confirm that the disabled port received no data.
        CHECK(rd2.get_read_ready() == 0);
    }

    // Timeout waiting for a partial read.
    SECTION("read_timeout") {
        // Write a complete packet, and discard the first port's output.
        satcat5::test::TimerSimulation timer;
        CHECK(pkt1->copy_and_finalize(&wr1));
        satcat5::poll::service_all();
        rd1.read_finalize();
        // Check the second port before and after timeout interval.
        CHECK(rd2.get_read_ready() == pkt1->get_read_ready());
        timer.sim_wait(9 * SATCAT5_MBUFF_TIMEOUT / 10);
        CHECK(rd2.get_read_ready() == pkt1->get_read_ready());
        timer.sim_wait(2 * SATCAT5_MBUFF_TIMEOUT / 10);
        CHECK(rd2.get_read_ready() == 0);
    }

    // Confirm that aborting a write frees associated memory.
    SECTION("write_abort_free") {
        write_random_bytes(&wr1, 1234);
        CHECK(mbuff.get_free_bytes() < capacity);
        wr1.write_abort();
        CHECK(mbuff.get_free_bytes() == capacity);
    }

    // Test that writes exceeding the maximum packet length are rejected.
    SECTION("write_maxlen") {
        // Write data in short sections until it overflows.
        // As soon as the overflow occurs, it should free the working buffer.
        unsigned write_total = 0;
        while (SATCAT5_MBUFF_PKTLEN < write_total) {
            write_random_bytes(&wr1, 123);
            write_total += 123;
            if (write_total <= SATCAT5_MBUFF_PKTLEN)
                CHECK(mbuff.get_free_bytes() < capacity);
            else
                CHECK(mbuff.get_free_bytes() == capacity);
        }
        // Finalizing an overflow packet should fail.
        CHECK_FALSE(wr1.write_finalize());
    }

    // Timeout waiting for a partial write.
    SECTION("write_timeout") {
        // Write a partial packet.
        satcat5::test::TimerSimulation timer;
        LimitedRead(pkt1, 42).copy_to(&wr1);
        CHECK(mbuff.get_free_bytes() < capacity);
        // Check buffer status before and after the timeout interval.
        timer.sim_wait(9 * SATCAT5_MBUFF_TIMEOUT / 10);
        CHECK(mbuff.get_free_bytes() < capacity);
        timer.sim_wait(2 * SATCAT5_MBUFF_TIMEOUT / 10);
        CHECK(mbuff.get_free_bytes() == capacity);
    }

    // Throughput benchmark.
    SECTION("throughput") {
        // Send and consume 125 packets, each 1000 bytes = 1 Mbit total
        satcat5::util::PosixTimer timer;
        auto tref = timer.now();
        for (unsigned a = 0 ; a < 125 ; ++a) {
            for (unsigned n = 0 ; n < 250 ; ++n)
                wr1.write_u32(satcat5::test::rand_u32());
            REQUIRE(wr1.write_finalize());
            satcat5::poll::service_all();
            REQUIRE(rd1.get_read_ready() == 1000);
            rd1.read_finalize();
            REQUIRE(rd2.get_read_ready() == 1000);
            rd2.read_finalize();
        }
        // Report the elapsed time.
        unsigned elapsed = tref.elapsed_usec();
        printf("MultiBuffer throughput: 1 Mbit / %u usec = %.1f Mbps\n",
            elapsed, 1e6f / elapsed);
    }

    // After each test, confirm buffer is still in a self-consistent state.
    CHECK(mbuff.consistency());
}

TEST_CASE("MultiReaderRandom") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    constexpr unsigned OPCOUNT = 4000;
    RefQueue ref;

    // Primary buffer with one write port.
    u8 raw_buff[16384];
    MultiBuffer mbuff(raw_buff, sizeof(raw_buff));
    MultiWriter wr(&mbuff);

    // Random test with MultiReaderSimple.
    SECTION("simple") {
        MultiReaderSimple rd(&mbuff);
        for (unsigned a = 0 ; a < OPCOUNT || rd.get_read_ready() ; ++a) {
            unsigned opcode = satcat5::test::rand_u32() % 256;
            if (a < OPCOUNT && opcode < 100 && rd.can_accept()) {
                // Attempt to push. If successful, update the reference.
                wr.write_u32(ref.index());
                if (wr.write_finalize()) ref.push(0);
                satcat5::poll::service_all();
            } else if (rd.get_read_ready() > 0) {
                // Attempt to pop, confirming expected index.
                u32 result = rd.read_u32();
                rd.read_finalize();
                CHECK(result == ref.pop());
            }
        }
    }

    // Random test with MultiReaderPriority.
    SECTION("priority") {
        MultiReaderPriority rd(&mbuff);
        for (unsigned a = 0 ; a < OPCOUNT || rd.get_read_ready() ; ++a) {
            unsigned opcode = satcat5::test::rand_u32() % 256;
            if (a < OPCOUNT && opcode < 100 && rd.can_accept()) {
                // Attempt to push. If successful, update the reference.
                // To confirm ties are resolved, limit unique priority values.
                u16 priority = u16(satcat5::test::rand_u8() % 8);
                wr.write_u32(ref.index());
                wr.set_priority(priority);
                if (wr.write_finalize()) ref.push(priority);
                satcat5::poll::service_all();
            } else if (rd.get_read_ready() > 0) {
                // Attempt to pop, confirming expected index.
                u32 result = rd.read_u32();
                rd.read_finalize();
                CHECK(result == ref.pop());
            }
            REQUIRE(rd.consistency());
        }
    }
}
