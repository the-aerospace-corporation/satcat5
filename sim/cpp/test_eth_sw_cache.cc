//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the Ethernet switch's address-cache plugin

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_sw_cache.h>

using satcat5::eth::ETYPE_PTP;
using satcat5::eth::MacAddr;
using satcat5::eth::MACADDR_BROADCAST;
using satcat5::eth::MACADDR_NONE;
using satcat5::eth::VTAG_NONE;
using satcat5::io::MultiPacket;

// Helper object for calling SwitchPlugin::query(...).
// (This test only requires a handful of fields...)
struct TestPacket {
    satcat5::io::MultiPacket pkt;
    satcat5::eth::SwitchPlugin::PacketMeta meta;

    TestPacket(MacAddr dst_mac, MacAddr src_mac, unsigned src_idx)
        : pkt{}
        , meta{}
    {
        pkt.m_length    = 0;
        pkt.m_refct     = 0;
        pkt.m_priority  = 0;
        pkt.m_user[0]   = (u32)src_idx;
        meta.pkt        = &pkt;
        meta.hdr        = {dst_mac, src_mac, ETYPE_PTP, VTAG_NONE};
        meta.dst_mask   = UINT32_MAX;
    }
};

TEST_CASE("eth_sw_cache") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Define the MAC address and port number for test devices.
    const MacAddr TEST_MAC[] = {
        {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}},
        {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}},
        {{0xDE, 0xAD, 0xBE, 0xEF, 0x33, 0x33}},
        {{0xDE, 0xAD, 0xBE, 0xEF, 0x44, 0x44}},
        {{0xDE, 0xAD, 0xBE, 0xEF, 0x55, 0x55}},
        {{0xDE, 0xAD, 0xBE, 0xEF, 0x66, 0x66}},
    };
    const unsigned TEST_PORT[] = {1, 2, 3, 4, 5, 6};

    // Unit under test.
    constexpr unsigned TBL_SIZE = 4;
    satcat5::eth::SwitchCache<TBL_SIZE> uut(0);

    // Temporary variables used for the SwitchCache API.
    unsigned tmp_idx;
    satcat5::eth::MacAddr tmp_mac;

    // Pre-fill the table to full capacity.
    CHECK(uut.mactbl_write(TEST_PORT[0], TEST_MAC[0]));
    CHECK(uut.mactbl_write(TEST_PORT[1], TEST_MAC[1]));
    CHECK(uut.mactbl_write(TEST_PORT[2], TEST_MAC[2]));
    CHECK(uut.mactbl_write(TEST_PORT[3], TEST_MAC[3]));

    // Exercise the main "query" function.
    SECTION("query_basic") {
        // Send a packet to each of the pre-loaded ports.
        TestPacket pkt0(TEST_MAC[0], TEST_MAC[1], TEST_PORT[1]);
        TestPacket pkt1(TEST_MAC[1], TEST_MAC[2], TEST_PORT[2]);
        TestPacket pkt2(TEST_MAC[2], TEST_MAC[3], TEST_PORT[3]);
        TestPacket pkt3(TEST_MAC[3], TEST_MAC[4], TEST_PORT[4]);
        TestPacket pkt4(TEST_MAC[4], TEST_MAC[3], TEST_PORT[3]);
        CHECK(uut.query(pkt0.meta));
        CHECK(uut.query(pkt1.meta));
        CHECK(uut.query(pkt2.meta));
        CHECK(uut.query(pkt3.meta));
        CHECK(pkt0.meta.dst_mask == 1u << TEST_PORT[0]);
        CHECK(pkt1.meta.dst_mask == 1u << TEST_PORT[1]);
        CHECK(pkt2.meta.dst_mask == 1u << TEST_PORT[2]);
        CHECK(pkt3.meta.dst_mask == 1u << TEST_PORT[3]);
        // Last query above contains a new address, confirm it was learned.
        CHECK(uut.query(pkt4.meta));
        CHECK(pkt4.meta.dst_mask == 1u << TEST_PORT[4]);
    }

    // Test query logic for reserved addresses.
    SECTION("query_rsvd") {
        TestPacket pkt_bcast(MACADDR_BROADCAST, TEST_MAC[0], TEST_PORT[0]);
        TestPacket pkt_none(MACADDR_NONE, TEST_MAC[0], TEST_PORT[0]);
        CHECK(uut.query(pkt_bcast.meta));
        CHECK(uut.query(pkt_none.meta));
        CHECK(pkt_bcast.meta.dst_mask == UINT32_MAX);
        CHECK(pkt_none.meta.dst_mask == 0);
    }

    // Test query logic for a cache miss (default = broadcast).
    SECTION("query_miss") {
        TestPacket pkt_miss(TEST_MAC[4], TEST_MAC[0], TEST_PORT[0]);
        CHECK(uut.query(pkt_miss.meta));
        CHECK(pkt_miss.meta.dst_mask == UINT32_MAX);
    }

    // Exercise the miss-as-broadcast controls.
    SECTION("miss_bcast") {
        CHECK(uut.get_miss_mask() == 0xFFFFFFFFu);
        uut.set_miss_bcast(0, false);
        uut.set_miss_bcast(2, false);
        uut.set_miss_bcast(3, false);
        CHECK(uut.get_miss_mask() == 0xFFFFFFF2u);
        uut.set_miss_bcast(2, true);
        CHECK(uut.get_miss_mask() == 0xFFFFFFF6u);
    }

    // Exercise the "mactbl_read" function.
    SECTION("mactbl_read") {
        // Out-of-bounds read should fail.
        CHECK_FALSE(uut.mactbl_read(TBL_SIZE, tmp_idx, tmp_mac));
        // Normal reads should succeed.
        for (unsigned a = 0 ; a < TBL_SIZE ; ++a) {
            CHECK(uut.mactbl_read(a, tmp_idx, tmp_mac));
            CHECK(tmp_idx > 0);
            if (tmp_idx == TEST_PORT[0]) CHECK(tmp_mac == TEST_MAC[0]);
            if (tmp_idx == TEST_PORT[1]) CHECK(tmp_mac == TEST_MAC[1]);
            if (tmp_idx == TEST_PORT[2]) CHECK(tmp_mac == TEST_MAC[2]);
            if (tmp_idx == TEST_PORT[3]) CHECK(tmp_mac == TEST_MAC[3]);
        }
    }

    // Exercise the "mactbl_clear" and "mactbl_learn" functions.
    SECTION("mactbl_clear") {
        TestPacket pkt0(TEST_MAC[0], TEST_MAC[1], TEST_PORT[1]);
        TestPacket pkt1(TEST_MAC[1], TEST_MAC[0], TEST_PORT[0]);
        TestPacket pkt2(TEST_MAC[0], TEST_MAC[1], TEST_PORT[1]);
        TestPacket pkt3(TEST_MAC[1], TEST_MAC[0], TEST_PORT[0]);
        TestPacket pkt4(TEST_MAC[0], TEST_MAC[1], TEST_PORT[1]);
        TestPacket pkt5(TEST_MAC[1], TEST_MAC[0], TEST_PORT[0]);
        CHECK(uut.query(pkt0.meta));
        CHECK(uut.query(pkt1.meta));
        uut.mactbl_clear();                     // Clear and send two packets
        uut.mactbl_learn(true);                 // (With learning enabled)
        CHECK(uut.query(pkt2.meta));
        CHECK(uut.query(pkt3.meta));
        uut.mactbl_clear();                     // Clear and send two packets
        uut.mactbl_learn(false);                // (With learning disabled)
        CHECK(uut.query(pkt4.meta));
        CHECK(uut.query(pkt5.meta));
        CHECK(pkt0.meta.dst_mask == 1u << TEST_PORT[0]);   // Pre-loaded addresses
        CHECK(pkt1.meta.dst_mask == 1u << TEST_PORT[1]);   // Pre-loaded addresses
        CHECK(pkt2.meta.dst_mask == UINT32_MAX);           // After clear (miss)
        CHECK(pkt3.meta.dst_mask == 1u << TEST_PORT[1]);   // After clear (just learned)
        CHECK(pkt4.meta.dst_mask == UINT32_MAX);           // No learning (miss)
        CHECK(pkt5.meta.dst_mask == UINT32_MAX);           // No learning (miss)
    }
}
