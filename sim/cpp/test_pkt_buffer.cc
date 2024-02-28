//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for packet buffer

#include <string.h>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/pkt_buffer.h>

using satcat5::io::PacketBuffer;
using satcat5::test::IoEventCounter;

#define BUF_SIZE 2048
#define BIG_BUF_SIZE (1<<17)

const u32 WRITE_ERROR = (u32)(-1);

TEST_CASE("Empty packet buffers are empty", "[pkt_buffer]") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    u8 buf_backing[BUF_SIZE];

    SECTION("Buffer without max_pkt") {
        PacketBuffer uut(buf_backing, BUF_SIZE);
        CHECK((u32)uut.get_percent_full() == 0);
        CHECK(uut.get_write_space() <= BUF_SIZE);
        CHECK(uut.get_read_ready() == 0);
    }
    SECTION("Buffer with max_pkt") {
        PacketBuffer uut(buf_backing, BUF_SIZE, 1);
        CHECK((u32)uut.get_percent_full() == 0);
        CHECK(uut.get_write_space() <= BUF_SIZE);
        CHECK(uut.get_read_ready() == 0);
    }
    SECTION("Buffer with odd length") {
        PacketBuffer uut(buf_backing, 35, 5);
        CHECK((u32)uut.get_percent_full() == 0);
        CHECK(uut.get_write_space() <= 35);
        CHECK(uut.get_read_ready() == 0);
    }
    SECTION("Tiny Buffer") {
        PacketBuffer uut(buf_backing, 1);
        CHECK((u32)uut.get_percent_full() == 0);
        CHECK(uut.get_write_space() <= 1);
        CHECK(uut.get_read_ready() == 0);
    }
    SECTION("Underflow without max_pkt") {
        PacketBuffer uut(buf_backing, BUF_SIZE, 0);
        uut.write_u16(1234);
        CHECK(uut.write_finalize());
        CHECK(uut.get_read_ready() == 2);
        uut.read_u32();
        CHECK(uut.get_read_ready() <= 2);
        uut.read_bytes(3, 0);
        CHECK(uut.get_read_ready() <= 2);
    }
}

TEST_CASE("normal writes to non-packet buffers", "[pkt_buffer]") {
    u8 buf_backing[BIG_BUF_SIZE];
    u8 buf_data[BIG_BUF_SIZE];
    unsigned bytes_written = 0;

    PacketBuffer uut(buf_backing, BIG_BUF_SIZE);

    // Buffer starts out empty
    REQUIRE((u32)uut.get_percent_full() == 0);
    u32 original_write_space = uut.get_write_space();

    // Do a small write
    uut.write_u8('a');
    ++bytes_written;
    // small enough to be 0%
    CHECK(uut.get_percent_full() == 0);
    CHECK(uut.get_write_partial() == bytes_written);

    // Do different writes
    SECTION("Writes of different sizes") {
        unsigned nbytes_cases = GENERATE(0, 1, BIG_BUF_SIZE/3, BIG_BUF_SIZE-2, BIG_BUF_SIZE-1);
        uut.write_bytes(nbytes_cases, buf_data);
        bytes_written += nbytes_cases;

        // The whole buffer is a "pakcet"
        u32 used_space = uut.get_write_partial();
        u32 free_space = uut.get_write_space();
        CHECK(used_space == bytes_written);
        CHECK(free_space + used_space == original_write_space);

        //PacketBuffer uut_copy = std::copy(uut);

        // Check that the correct size is written
        SECTION("Data is present after finalize") {
            uut.write_finalize();
            CHECK(uut.get_write_partial() == 0);
            CHECK(uut.get_write_space() == free_space);
        }
        SECTION("Data is erased after abort") {
            uut.write_abort();
            CHECK(uut.get_write_partial() == 0);
            CHECK((u32)uut.get_percent_full() == 0);
            CHECK(uut.get_write_space() == original_write_space);
        }
    }

    // Buffer returns to empty after clear
    uut.clear();
    REQUIRE(uut.get_write_partial() == 0);
    REQUIRE((u32)uut.get_percent_full() == 0);
    REQUIRE(uut.get_write_space() == original_write_space);
}

TEST_CASE("zero-size write", "[pkt_buffer]") {
    u8 buf_backing[BUF_SIZE];
    u8 buf_data[BUF_SIZE];

    PacketBuffer uut(buf_backing, BUF_SIZE);

    // Buffer starts out empty
    REQUIRE((u32)uut.get_percent_full() == 0);
    u32 original_write_space = uut.get_write_space();

    // Write nothing
    uut.write_bytes(0, buf_data);
    CHECK(uut.get_percent_full() == 0);
    CHECK(uut.get_write_partial() == 0);

    // Try to commit or revert that 0
    SECTION("Data is present after finalize") {
        uut.write_finalize();
        CHECK(uut.get_write_partial() == 0);
        CHECK((u32)uut.get_percent_full() == 0);
        CHECK(uut.get_write_space() == original_write_space);
    }
    SECTION("Data is erased after abort") {
        uut.write_abort();
        CHECK(uut.get_write_partial() == 0);
        CHECK((u32)uut.get_percent_full() == 0);
        CHECK(uut.get_write_space() == original_write_space);
    }

    // Buffer returns to empty after clear
    uut.clear();
    REQUIRE(uut.get_write_partial() == 0);
    REQUIRE((u32)uut.get_percent_full() == 0);
    REQUIRE(uut.get_write_space() == original_write_space);
}


TEST_CASE("Abandon packet on oversize write", "[pkt_buffer]") {
    u8 buf_backing[BUF_SIZE];
    u8 buf_data[BUF_SIZE];

    PacketBuffer uut(buf_backing, BUF_SIZE);
    u32 original_write_space = uut.get_write_space();

    // Write a single byte packet
    uut.write_u8('a');
    uut.write_finalize();
    CHECK(uut.get_write_space() == original_write_space-1);

    // Write to almost full
    uut.write_bytes(original_write_space-3, buf_data);
    CHECK(uut.get_percent_full() == 99);
    CHECK(uut.get_write_partial() == original_write_space-3);
    CHECK(uut.get_write_space() == 2);

    // Different paths to overflow
    SECTION("Overflow the buffer") {
        unsigned write_sizes = GENERATE(1,2,4,5,100,BUF_SIZE);
        switch(write_sizes) {
            case 1:
                uut.write_u8('a');
                uut.write_u8('a');
                uut.write_u8('a');
                uut.write_u8('a');
                break;
            case 2:
                uut.write_u16(1000);
                uut.write_u16(1000);
                break;
            case 4:
                uut.write_u32(-1);
                break;
            default:
                uut.write_bytes(write_sizes, buf_data);
                break;
        }

        // Should show overflow
        CHECK(uut.get_percent_full() == 100);
        CHECK(uut.get_write_space() == 0);
        CHECK(uut.get_write_partial() == WRITE_ERROR);


        // Try to commit or revert
        SECTION("Data is erased after finalize") {
            uut.write_finalize();
        }
        SECTION("Data is erased after abort") {
            uut.write_abort();
        }
            CHECK(uut.get_write_partial() == 0);
            CHECK((u32)uut.get_percent_full() == 0);
            CHECK(uut.get_write_space() == original_write_space-1);
    }

    // Buffer returns to empty after clear
    uut.clear();
    REQUIRE(uut.get_write_partial() == 0);
    REQUIRE((u32)uut.get_percent_full() == 0);
    REQUIRE(uut.get_write_space() == original_write_space);
}


TEST_CASE("large packet", "[pkt_buffer]") {
    u8 buf_backing[BIG_BUF_SIZE];
    u8 buf_data[BIG_BUF_SIZE];
    unsigned big_write_size = (1<<16)+1;
    unsigned bytes_written = 0;

    PacketBuffer uut(buf_backing, BIG_BUF_SIZE, 2);

    // Buffer starts out empty
    REQUIRE((u32)uut.get_percent_full() == 0);

    // Write a small packet
    uut.write_u8('a');
    ++bytes_written;
    bool small_result = uut.write_finalize();
    u32 small_space = uut.get_write_space();
    CHECK(small_result == true);

    // Write 0xFFFF+1 bytes
    uut.write_bytes(big_write_size, buf_data);
    bytes_written += big_write_size;
    // Should overflow
    CHECK(uut.get_write_partial() == WRITE_ERROR);
    CHECK(uut.get_write_space() == 0);

    // Commit should fail
    bool big_result = uut.write_finalize();
    REQUIRE(big_result == false);
    CHECK(uut.get_write_partial() == 0);
    CHECK(uut.get_write_space() == small_space);

    // Read the small packet
    REQUIRE(uut.get_read_ready() == 1);
    u8 val = uut.read_u8();
    REQUIRE(val == 'a');

    // No more packets
    REQUIRE(uut.get_read_ready() == 0);
    uut.read_finalize();
    REQUIRE(uut.get_read_ready() == 0);
}

// Test write after read, including wrap around get_write_space
TEST_CASE("wrap-around read", "[pkt_buffer]") {
    u8 buf_backing[500];
    u8 buf_src[500];
    u8 buf_dst[500];
    unsigned bytes_written = 0;

    PacketBuffer uut(buf_backing, 500, 5);

    // Buffer starts out empty
    REQUIRE((u32)uut.get_percent_full() == 0);
    u32 original_write_space = uut.get_write_space();

    // Write a 100-byte packet
    uut.write_bytes(100, buf_src);
    uut.write_finalize();
    bytes_written += 100;

    // Write a bit of a second packet
    uut.write_bytes(25, buf_src);
    bytes_written += 25;

    // Read part of the first packet
    CHECK(uut.get_read_ready() == 100);
    uut.read_u16();
    CHECK(uut.get_read_ready() == 98);
    bytes_written -= 2;

    // Finish the second 100-byte packet
    uut.write_bytes(75, buf_src);
    uut.write_finalize();
    bytes_written += 75;
    u8 filled_pct = uut.get_percent_full();
    CHECK(filled_pct > 0);

    // Finish reading the first packet
    CHECK(uut.get_read_ready() == 98);
    uut.read_bytes(98, buf_dst);
    bytes_written -= 98;
    CHECK(uut.get_read_ready() == 0);
    uut.read_finalize();

    // Second packet is ready
    CHECK(uut.get_read_ready() == 100);
    CHECK(uut.get_write_partial() == 0);
    CHECK(uut.get_write_space() + bytes_written == original_write_space);

    // Should have room for about 400 bytes now
    CHECK(uut.get_percent_full() < filled_pct);
    CHECK(uut.get_write_space() + bytes_written == original_write_space);

    // Write a packet that wraps around (with known data)
    memset(buf_src, 'w', 500);
    uut.write_bytes(370, buf_src);
    uut.write_finalize();
    bytes_written += 370;
    CHECK(uut.get_write_partial() == 0);
    CHECK(uut.get_write_space() + bytes_written == original_write_space);

    // Read the second packet
    CHECK(uut.get_read_ready() == 100);
    uut.read_bytes(100, buf_dst);
    bytes_written -= 100;
    CHECK(uut.get_read_ready() == 0);
    uut.read_finalize();
    CHECK(uut.get_write_space() + bytes_written == original_write_space);

    // Read the third packet
    CHECK(uut.get_percent_full() > 0);
    CHECK(uut.get_read_ready() == 370);
    uut.read_bytes(370, buf_dst);
    bytes_written -= 370;
    // Check that buf_dst data is correct
    int cmp_result = memcmp(buf_src, buf_dst, 370);
    CHECK(cmp_result == 0);
    uut.read_finalize();

    // Empty again
    REQUIRE(bytes_written == 0); // Sanity check on test
    CHECK(uut.get_percent_full() == 0);
    REQUIRE(uut.get_write_partial() == 0);
    REQUIRE(uut.get_write_space() == original_write_space);
}

TEST_CASE("zero-copy write", "[pkt_buffer]") {
    u8 buf_backing[256];
    u8* wrptr = 0;
    PacketBuffer uut(buf_backing, sizeof(buf_backing), 2);
    unsigned maxbuff = uut.get_write_space();

    // Write a short frame using Zero-copy-write API
    CHECK(uut.zcw_maxlen() == maxbuff);
    wrptr = uut.zcw_start();
    CHECK(wrptr);
    wrptr[0] = 'a';
    wrptr[1] = 'b';
    wrptr[2] = 'c';
    uut.zcw_write(3);
    CHECK(uut.write_finalize());

    // Write a second short frame.
    CHECK(uut.zcw_maxlen() == maxbuff - 3);
    wrptr = uut.zcw_start();
    CHECK(wrptr);
    wrptr[0] = 'd';
    wrptr[1] = 'e';
    uut.zcw_write(2);
    CHECK(uut.write_finalize());

    // Attempts to write a third frame should be rejected.
    CHECK(uut.get_write_space() == 0);
    CHECK(uut.zcw_maxlen() == 0);
    uut.zcw_write(1);
    CHECK(!uut.write_finalize());

    // Read both frames.
    CHECK(uut.get_read_ready() == 3);
    CHECK(uut.read_u8() == 'a');
    CHECK(uut.read_u8() == 'b');
    CHECK(uut.read_u8() == 'c');
    uut.read_finalize();
    CHECK(uut.get_read_ready() == 2);
    CHECK(uut.read_u8() == 'd');
    CHECK(uut.read_u8() == 'e');
    uut.read_finalize();
    CHECK(uut.get_read_ready() == 0);
}

TEST_CASE("zero-copy full1", "[pkt_buffer]") {
    u8 buf_backing[256];
    PacketBuffer uut(buf_backing, sizeof(buf_backing), 1);

    // Write one short packet to fill buffer.
    uut.write_u32(1234);
    CHECK(uut.write_finalize());
    CHECK(uut.get_write_space() == 0);

    // Confirm ZCW-write reports full.
    CHECK(uut.zcw_maxlen() == 0);
}

TEST_CASE("zero-copy full2", "[pkt_buffer]") {
    u8 buf_backing[256];
    PacketBuffer uut(buf_backing, sizeof(buf_backing), 10);

    // Write one long packet to fill buffer.
    while (uut.get_write_space())
        uut.write_u8(0x42);
    CHECK(uut.write_finalize());
    CHECK(uut.get_write_space() == 0);

    // Confirm ZCW-write reports full.
    CHECK(uut.zcw_maxlen() == 0);
}

TEST_CASE("underflow read", "[pkt_buffer]") {
    u8 buf_backing[256], buf_test[256];
    PacketBuffer uut(buf_backing, sizeof(buf_backing), 2);

    // Empty buffer, all reads should fail.
    CHECK(uut.get_read_ready() == 0);
    CHECK(uut.peek(7) == 0);
    CHECK(!uut.read_bytes(8, buf_test));
    CHECK(!uut.read_consume(5));

    // Write two short packets.
    uut.write_u8('a');
    uut.write_u8('b');
    uut.write_u8('c');
    CHECK(uut.write_finalize());
    uut.write_u8('d');
    uut.write_u8('e');
    uut.write_u8('f');
    CHECK(uut.write_finalize());

    // Attempt to read too many bytes using various methods.
    // Note: Each SECTION runs the code before and after in a new instance.
    CHECK(uut.get_read_ready() == 3);
    SECTION("read_u32")
        {CHECK(uut.read_u32() == 0);}
    SECTION("read_bytes")
        {CHECK(!uut.read_bytes(8, buf_test));}
    SECTION("peek")
        {CHECK(uut.peek(6) == 0);}
    SECTION("consume")
        {CHECK(!uut.read_consume(5));}
    uut.read_finalize();

    // Next packet should still be OK.
    CHECK(uut.get_read_ready() == 3);
    CHECK(uut.read_u8() == 'd');
    CHECK(uut.read_u8() == 'e');
    CHECK(uut.read_u8() == 'f');
    uut.read_finalize();
    CHECK(uut.get_read_ready() == 0);
}

TEST_CASE("Write too many packets", "[pkt_buffer]") {
    u8 buf_backing[256];
    PacketBuffer uut(buf_backing, sizeof(buf_backing), 2);

    // Write first packet (success)
    uut.write_u8('a');
    CHECK(uut.write_finalize());

    // Write second packet (success)
    uut.write_u8('b');
    CHECK(uut.write_finalize());

    // Write third packet (overflow)
    uut.write_u8('c');
    CHECK(!uut.write_finalize());

    // Read back both successful packets.
    CHECK(uut.get_read_ready() == 1);
    CHECK(uut.read_u8() == 'a');
    uut.read_finalize();
    CHECK(uut.get_read_ready() == 1);
    CHECK(uut.read_u8() == 'b');
    uut.read_finalize();
    CHECK(uut.get_read_ready() == 0);
}

TEST_CASE("Notifications") {
    // Unit under test with working buffer.
    u8 buf_backing[256];
    PacketBuffer uut(buf_backing, sizeof(buf_backing), 16);

    // Link to an event handler.
    IoEventCounter ctr;
    uut.set_callback(&ctr);

    // Write a few packets.
    uut.write_u8('a');
    CHECK(uut.write_finalize());
    uut.write_u8('b');
    uut.write_u8('c');
    CHECK(uut.write_finalize());

    // Run a few service-loop iterations.
    CHECK(ctr.count() == 0);    // No notifications yet...
    satcat5::poll::service();
    CHECK(ctr.count() == 1);    // 1st notification (1st pkt)
    satcat5::poll::service();
    CHECK(ctr.count() == 2);    // 2nd notification (1st pkt)
    CHECK(uut.get_read_ready() == 1);
    uut.read_finalize();        // Discard first packet
    satcat5::poll::service();
    CHECK(ctr.count() == 3);    // 3rd notification (2nd pkt)
    CHECK(uut.get_read_ready() == 2);
    uut.read_finalize();        // Discard second packet
    satcat5::poll::service();
    CHECK(ctr.count() == 3);    // No 4th notification
    CHECK(uut.get_read_ready() == 0);
}
