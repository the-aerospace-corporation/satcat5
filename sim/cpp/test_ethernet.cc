//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for Ethernet-related data structures

#include <hal_test/catch.hpp>
#include <satcat5/ethernet.h>

namespace eth   = satcat5::eth;
namespace io    = satcat5::io;

TEST_CASE("ethernet-mac") {
    // Values for these constants are arbitrary.
    const eth::MacAddr MACADDR_A =
        {{0x42, 0x42, 0x42, 0x42, 0x42, 0x42}};
    const eth::MacAddr MACADDR_B =
        {{0x42, 0x42, 0x42, 0x41, 0x42, 0x42}};
    const eth::MacAddr MACADDR_C =
        {{0x42, 0x42, 0x42, 0x42, 0x43, 0x42}};
    const eth::MacType MACTYPE = {0xAABB};
    const eth::Header HEADER_AB =
        {MACADDR_A, MACADDR_B, MACTYPE, eth::VTAG_NONE};

    // Set up a small working buffer.
    u8 buffer[64];
    io::ArrayWrite wr(buffer, sizeof(buffer));

    SECTION("equal") {
        CHECK(MACADDR_A == MACADDR_A);
        CHECK(!(MACADDR_A == MACADDR_B));
        CHECK(!(MACADDR_A == MACADDR_C));
        CHECK(!(MACADDR_B == MACADDR_A));
        CHECK(MACADDR_B == MACADDR_B);
        CHECK(!(MACADDR_B == MACADDR_C));
        CHECK(!(MACADDR_C == MACADDR_A));
        CHECK(!(MACADDR_C == MACADDR_B));
        CHECK(MACADDR_C == MACADDR_C);
    }

    SECTION("not-equal") {
        CHECK(!(MACADDR_A != MACADDR_A));
        CHECK(MACADDR_A != MACADDR_B);
        CHECK(MACADDR_A != MACADDR_C);
        CHECK(MACADDR_B != MACADDR_A);
        CHECK(!(MACADDR_B != MACADDR_B));
        CHECK(MACADDR_B != MACADDR_C);
        CHECK(MACADDR_C != MACADDR_A);
        CHECK(MACADDR_C != MACADDR_B);
        CHECK(!(MACADDR_C != MACADDR_C));
    }

    SECTION("compare") {
        CHECK(MACADDR_B < MACADDR_A);
        CHECK(MACADDR_A < MACADDR_C);
        CHECK(MACADDR_B < MACADDR_C);
        CHECK(!(MACADDR_B < MACADDR_B));
    }

    SECTION("to_from") {
        CHECK(MACADDR_B.to_u64() == 0x424242414242ULL);
        CHECK(MACADDR_C == eth::MacAddr::from_u64(0x424242424342ULL));
    }

    SECTION("read-write") {
        // Write the example header to buffer.
        HEADER_AB.write_to(&wr);
        wr.write_finalize();

        // Now check the contents, byte for byte.
        REQUIRE(wr.written_len() == 14);
        CHECK(buffer[0] == MACADDR_A.addr[0]);  // Dst
        CHECK(buffer[1] == MACADDR_A.addr[1]);
        CHECK(buffer[2] == MACADDR_A.addr[2]);
        CHECK(buffer[3] == MACADDR_A.addr[3]);
        CHECK(buffer[4] == MACADDR_A.addr[4]);
        CHECK(buffer[5] == MACADDR_A.addr[5]);
        CHECK(buffer[6] == MACADDR_B.addr[0]);  // Src
        CHECK(buffer[7] == MACADDR_B.addr[1]);
        CHECK(buffer[8] == MACADDR_B.addr[2]);
        CHECK(buffer[9] == MACADDR_B.addr[3]);
        CHECK(buffer[10] == MACADDR_B.addr[4]);
        CHECK(buffer[11] == MACADDR_B.addr[5]);
        CHECK(buffer[12] == 0xAA);              // Etype
        CHECK(buffer[13] == 0xBB);

        // Read new header from buffer, and check all fields match.
        io::ArrayRead rd(buffer, wr.written_len());
        eth::Header hdr;
        CHECK(hdr.read_from(&rd));
        CHECK(hdr.dst == MACADDR_A);
        CHECK(hdr.src == MACADDR_B);
        CHECK(hdr.type == MACTYPE);

        // Read it again using different methods.
        rd.read_finalize();
        eth::MacAddr addr;
        eth::MacType etype;
        CHECK(addr.read_from(&rd));
        CHECK(addr == MACADDR_A);
        CHECK(addr.read_from(&rd));
        CHECK(addr == MACADDR_B);
        CHECK(etype.read_from(&rd));
        CHECK(etype == MACTYPE);
    }

    SECTION("read-write-vtag") {
        // Write the example header to buffer.
        eth::Header hdr1 = HEADER_AB;
        hdr1.vtag.value = 0x1234;
        hdr1.write_to(&wr);
        wr.write_finalize();

        // Now check the contents, byte for byte.
        REQUIRE(wr.written_len() == 18);
        CHECK(buffer[0] == MACADDR_A.addr[0]);  // Dst
        CHECK(buffer[1] == MACADDR_A.addr[1]);
        CHECK(buffer[2] == MACADDR_A.addr[2]);
        CHECK(buffer[3] == MACADDR_A.addr[3]);
        CHECK(buffer[4] == MACADDR_A.addr[4]);
        CHECK(buffer[5] == MACADDR_A.addr[5]);
        CHECK(buffer[6] == MACADDR_B.addr[0]);  // Src
        CHECK(buffer[7] == MACADDR_B.addr[1]);
        CHECK(buffer[8] == MACADDR_B.addr[2]);
        CHECK(buffer[9] == MACADDR_B.addr[3]);
        CHECK(buffer[10] == MACADDR_B.addr[4]);
        CHECK(buffer[11] == MACADDR_B.addr[5]);
        CHECK(buffer[12] == 0x81);              // VLAN tag
        CHECK(buffer[13] == 0x00);
        CHECK(buffer[14] == 0x12);
        CHECK(buffer[15] == 0x34);
        CHECK(buffer[16] == 0xAA);              // Etype
        CHECK(buffer[17] == 0xBB);

        // Read new header from buffer, and check all fields match.
        io::ArrayRead rd(buffer, wr.written_len());
        eth::Header hdr2;
        CHECK(hdr2.read_from(&rd));
        CHECK(hdr2.dst == MACADDR_A);
        CHECK(hdr2.src == MACADDR_B);
        CHECK(hdr2.type == MACTYPE);
        CHECK(hdr2.vtag.value == 0x1234);
    }

    SECTION("read-error") {
        // Write a partial header to the buffer.
        MACADDR_A.write_to(&wr);
        wr.write_finalize();

        // Confirm attempted read fails.
        io::ArrayRead rd(buffer, wr.written_len());
        eth::Header hdr;
        CHECK(!hdr.read_from(&rd));
    }

    SECTION("read-error-vtag") {
        // Write a partial header to the buffer.
        MACADDR_A.write_to(&wr);
        MACADDR_B.write_to(&wr);
        satcat5::eth::ETYPE_VTAG.write_to(&wr);
        wr.write_finalize();

        // Confirm attempted read fails.
        io::ArrayRead rd(buffer, wr.written_len());
        eth::Header hdr;
        CHECK(!hdr.read_from(&rd));
    }
}
