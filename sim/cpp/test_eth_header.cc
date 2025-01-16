//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for Ethernet-related data structures

#include <hal_posix/posix_utils.h>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ethernet.h>

using satcat5::eth::BASEADDR_L2MULTICAST;
using satcat5::eth::BASEADDR_L3MULTICAST;
using satcat5::eth::BASEADDR_LINKLOCAL;
using satcat5::eth::MACADDR_BROADCAST;
using satcat5::eth::MACADDR_FLOWCTRL;
using satcat5::eth::MACADDR_NONE;
namespace eth   = satcat5::eth;
namespace io    = satcat5::io;

TEST_CASE("eth-header") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

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
    io::ArrayWriteStatic<64> wr;
    const u8* buffer = wr.buffer();

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

    SECTION("is_multicast") {
        CHECK(BASEADDR_L2MULTICAST.is_multicast());
        CHECK(BASEADDR_L3MULTICAST.is_multicast());
        CHECK_FALSE(BASEADDR_LINKLOCAL.is_multicast());
        CHECK_FALSE(MACADDR_FLOWCTRL.is_multicast());
        CHECK_FALSE(MACADDR_NONE.is_multicast());
        CHECK_FALSE(MACADDR_A.is_multicast());
        CHECK_FALSE(MACADDR_B.is_multicast());
        CHECK_FALSE(MACADDR_C.is_multicast());
        CHECK(MACADDR_BROADCAST.is_multicast());
    }

    SECTION("is_swcontrol") {
        CHECK_FALSE(BASEADDR_L2MULTICAST.is_swcontrol());
        CHECK_FALSE(BASEADDR_L3MULTICAST.is_swcontrol());
        CHECK(BASEADDR_LINKLOCAL.is_swcontrol());
        CHECK(MACADDR_FLOWCTRL.is_swcontrol());
        CHECK_FALSE(MACADDR_NONE.is_swcontrol());
        CHECK_FALSE(MACADDR_A.is_swcontrol());
        CHECK_FALSE(MACADDR_B.is_swcontrol());
        CHECK_FALSE(MACADDR_C.is_swcontrol());
        CHECK_FALSE(MACADDR_BROADCAST.is_swcontrol());
    }

    SECTION("is_unicast") {
        CHECK_FALSE(BASEADDR_L2MULTICAST.is_unicast());
        CHECK_FALSE(BASEADDR_L3MULTICAST.is_unicast());
        CHECK_FALSE(BASEADDR_LINKLOCAL.is_unicast());
        CHECK_FALSE(MACADDR_FLOWCTRL.is_unicast());
        CHECK_FALSE(MACADDR_NONE.is_unicast());
        CHECK(MACADDR_A.is_unicast());
        CHECK(MACADDR_B.is_unicast());
        CHECK(MACADDR_C.is_unicast());
        CHECK_FALSE(MACADDR_BROADCAST.is_unicast());
    }

    SECTION("is_valid") {
        CHECK(BASEADDR_L2MULTICAST.is_valid());
        CHECK(BASEADDR_L3MULTICAST.is_valid());
        CHECK(BASEADDR_LINKLOCAL.is_valid());
        CHECK(MACADDR_FLOWCTRL.is_valid());
        CHECK_FALSE(MACADDR_NONE.is_valid());
        CHECK(MACADDR_A.is_valid());
        CHECK(MACADDR_B.is_valid());
        CHECK(MACADDR_C.is_valid());
        CHECK(MACADDR_BROADCAST.is_valid());
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
        CHECK_FALSE(hdr1.vtag.any());
        hdr1.vtag.set(0x234, 1, 0);
        CHECK(hdr1.vtag.any());
        CHECK(hdr1.vtag.value == 0x1234);
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
        CHECK(hdr2.vtag == hdr1.vtag);
        CHECK(hdr2.vtag != eth::VlanTag{0x1235});
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

    SECTION("logging") {
        log.suppress("Test");  // Don't echo to screen.
        // Log a header without a VLAN tag.
        eth::Header hdr = HEADER_AB;
        satcat5::log::Log(satcat5::log::INFO, "Test1").write_obj(hdr);
        CHECK(log.contains("DstMAC = 42:42:42:42:42:42"));
        CHECK(log.contains("SrcMAC = 42:42:42:41:42:42"));
        CHECK(log.contains("EType  = 0xAABB"));
        CHECK_FALSE(log.contains("VlanID"));
        // Log a header with a VLAN tag.
        hdr.vtag.value = 0xB123;
        satcat5::log::Log(satcat5::log::INFO, "Test2").write_obj(hdr);
        CHECK(log.contains("VlanID = 0x123"));
        CHECK(log.contains("DropOK = 1"));
        CHECK(log.contains("Priority = 5"));
    }
}
