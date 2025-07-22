//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// CCSDS "Advanced Orbiting Systems" (AOS) Space Data Link Protocol

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ccsds_aos.h>
#include <satcat5/ccsds_spp.h>

// Make a valid SPP frame containing a string.
static std::string make_spp(u16 seq, satcat5::io::Readable& src) {
    // Create the SPP header.
    satcat5::ccsds_spp::Header hdr;
    hdr.set(true, 0x123, seq);
    REQUIRE(src.get_read_ready() > 0);
    // Write header and contents to a temporary buffer.
    satcat5::io::PacketBufferHeap tmp;
    tmp.write_u32(hdr.value);
    tmp.write_u16(src.get_read_ready() - 1);
    src.copy_and_finalize(&tmp);
    // Copy the complete SPP into an STL string.
    return satcat5::io::read_str(&tmp);
}

static std::string make_spp(u16 seq, const char* str) {
    satcat5::io::ArrayRead rd(strlen(str), str);
    return make_spp(seq, rd);
}

TEST_CASE("ccsds_aos") {
    SATCAT5_TEST_START;

    // Packet capture system for the simplex point-to-point link.
    satcat5::io::WritePcap phy_tx;
    phy_tx.open(
        satcat5::test::sim_filename(__FILE__, "pcap"),
        satcat5::io::LINKTYPE_AOS);
    satcat5::io::PacketBufferHeap phy_rx;
    phy_tx.set_passthrough(&phy_rx);

    // Attach CCSDS-AOS encoder and decoder devices to this link.
    satcat5::ccsds_aos::DispatchStatic<16> link_src(0, &phy_tx, true);
    satcat5::ccsds_aos::DispatchStatic<16> link_dst(&phy_rx, 0, true);

    // Attach a byte-stream and a packet stream to each device.
    satcat5::io::StreamBufferHeap srcb, dstb;
    satcat5::io::PacketBufferHeap srcp, dstp;
    satcat5::ccsds_aos::Channel ch_srcb(&link_src, &srcb, 0, 42, 43, false);
    satcat5::ccsds_aos::Channel ch_srcp(&link_src, &srcp, 0, 42, 44, true);
    satcat5::ccsds_aos::Channel ch_dstb(&link_dst, 0, &dstb, 42, 43, false);
    satcat5::ccsds_aos::Channel ch_dstp(&link_dst, 0, &dstp, 42, 44, true);

    // Read an example AOS header.
    SECTION("header") {
        constexpr u8 HDR[] = {0x40, 0x42, 0x23, 0x45, 0x67, 0x41};
        satcat5::io::ArrayRead hdr(HDR, sizeof(HDR));
        satcat5::ccsds_aos::Header uut;
        CHECK(uut.read_from(&hdr));
        CHECK(uut.version() == satcat5::ccsds_aos::VERSION_2);
        CHECK(uut.svid() == 1);
        CHECK(uut.vcid() == 2);
        CHECK(uut.count == 0x1234567);
        CHECK_FALSE(uut.replay());
    }

    // Basic test with a single AOS transfer frame of each type.
    SECTION("basic_short") {
        CHECK(satcat5::test::write(&srcb, "Short stream"));
        CHECK(satcat5::test::write(&srcp, make_spp(0, "Pkt")));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&dstb, "Short stream"));
        CHECK(satcat5::test::read(&dstp, make_spp(0, "Pkt")));
        CHECK(link_dst.frame_count() == 2);
    }

    // Longer test with packets split across several transfer frames.
    SECTION("basic_long") {
        // Send and receive a few AOS frames.
        CHECK(satcat5::test::write(&srcb, "Long stream spanning three frames."));
        CHECK(satcat5::test::write(&srcp, make_spp(0, "Several")));
        CHECK(satcat5::test::write(&srcp, make_spp(1, "shorter")));
        CHECK(satcat5::test::write(&srcp, make_spp(2, "packets")));
        CHECK(satcat5::test::write(&srcp, make_spp(3, "and one longer packet")));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&dstb, "Long stream spanning three frames."));
        CHECK(satcat5::test::read(&dstp, make_spp(0, "Several")));
        CHECK(satcat5::test::read(&dstp, make_spp(1, "shorter")));
        CHECK(satcat5::test::read(&dstp, make_spp(2, "packets")));
        CHECK(satcat5::test::read(&dstp, make_spp(3, "and one longer packet")));
        // Send one last SPP. (Initial M_PDU state is mid-idle-filler.)
        CHECK(satcat5::test::write(&srcp, make_spp(4, "one more")));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&dstp, make_spp(4, "one more")));
        CHECK(link_dst.frame_count() == 10);
    }

    // Hard-code the expected output from "basic_long".
    // (This also doubles as a test of our CRC calculation.)
    //  Sync                    Header                              PDU
    constexpr u8 PKT0[] = {
        0x1A, 0xCF, 0xFC, 0x1D, 0x4A, 0xAC, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x11, 0x23,
        0xC0, 0x00, 0x00, 0x06, 0x53, 0x65, 0x76, 0x65, 0x72, 0x61, 0x6C, 0x11, 0x22, 0x1A};
    constexpr u8 PKT1[] = {
        0x1A, 0xCF, 0xFC, 0x1D, 0x4A, 0xAC, 0x00, 0x00, 0x01, 0x40, 0x00, 0x0C, 0x23, 0xC0,
        0x01, 0x00, 0x06, 0x73, 0x68, 0x6F, 0x72, 0x74, 0x65, 0x72, 0x11, 0x23, 0xE6, 0x9D};
    constexpr u8 PKT2[] = {
        0x1A, 0xCF, 0xFC, 0x1D, 0x4A, 0xAC, 0x00, 0x00, 0x02, 0x40, 0x00, 0x0B, 0xC0, 0x02,
        0x00, 0x06, 0x70, 0x61, 0x63, 0x6B, 0x65, 0x74, 0x73, 0x11, 0x23, 0xC0, 0xC9, 0x56};
    constexpr u8 PKT3[] = {
        0x1A, 0xCF, 0xFC, 0x1D, 0x4A, 0xAC, 0x00, 0x00, 0x03, 0x40, 0x07, 0xFF, 0x03, 0x00,
        0x14, 0x61, 0x6E, 0x64, 0x20, 0x6F, 0x6E, 0x65, 0x20, 0x6C, 0x6F, 0x6E, 0xC1, 0xA2};
    constexpr u8 PKT4[] = {
        0x1A, 0xCF, 0xFC, 0x1D, 0x4A, 0xAC, 0x00, 0x00, 0x04, 0x40, 0x00, 0x0A, 0x67, 0x65,
        0x72, 0x20, 0x70, 0x61, 0x63, 0x6B, 0x65, 0x74, 0x07, 0xFF, 0x40, 0x00, 0x0D, 0x1C};
    constexpr u8 PKT5[] = {
        0x1A, 0xCF, 0xFC, 0x1D, 0x4A, 0xAC, 0x00, 0x00, 0x05, 0x40, 0x00, 0x03, 0x00, 0x00,
        0x00, 0x11, 0x23, 0xC0, 0x04, 0x00, 0x07, 0x6F, 0x6E, 0x65, 0x20, 0x6D, 0xA9, 0xFA};
    constexpr u8 PKT6[] = {
        0x1A, 0xCF, 0xFC, 0x1D, 0x4A, 0xAC, 0x00, 0x00, 0x06, 0x40, 0x00, 0x03, 0x6F, 0x72,
        0x65, 0x07, 0xFF, 0x40, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA1, 0xF5};

    // Test recovery after dropping various combinations of AOS frames.
    SECTION("drop0") {
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT1), PKT1));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT2), PKT2));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT3), PKT3));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT4), PKT4));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT5), PKT5));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT6), PKT6));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&dstp, make_spp(2, "packets")));
        CHECK(satcat5::test::read(&dstp, make_spp(3, "and one longer packet")));
        CHECK(satcat5::test::read(&dstp, make_spp(4, "one more")));
        CHECK(link_dst.error_count() == 1);
    }

    SECTION("drop1") {
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT0), PKT0));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT2), PKT2));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT3), PKT3));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT4), PKT4));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT5), PKT5));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT6), PKT6));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&dstp, make_spp(0, "Several")));
        CHECK(satcat5::test::read(&dstp, make_spp(3, "and one longer packet")));
        CHECK(satcat5::test::read(&dstp, make_spp(4, "one more")));
        CHECK(link_dst.error_count() == 1);
    }

    SECTION("drop2") {
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT0), PKT0));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT1), PKT1));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT3), PKT3));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT4), PKT4));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT5), PKT5));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT6), PKT6));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&dstp, make_spp(0, "Several")));
        CHECK(satcat5::test::read(&dstp, make_spp(1, "shorter")));
        CHECK(satcat5::test::read(&dstp, make_spp(4, "one more")));
        CHECK(link_dst.error_count() == 1);
    }

    SECTION("drop3") {
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT0), PKT0));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT1), PKT1));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT2), PKT2));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT4), PKT4));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT5), PKT5));
        CHECK(satcat5::test::write(&phy_tx, sizeof(PKT6), PKT6));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&dstp, make_spp(0, "Several")));
        CHECK(satcat5::test::read(&dstp, make_spp(1, "shorter")));
        CHECK(satcat5::test::read(&dstp, make_spp(2, "packets")));
        CHECK(satcat5::test::read(&dstp, make_spp(4, "one more")));
        CHECK(link_dst.error_count() == 1);
    }

    // Test a case where consecutive SPP frames fall *exactly*
    // on the boundary between AOS frames:
    // DSIZE = 2 byte MPDU header + 6 byte SPP header + SPP data
    // This test uses DSIZE = 16, so send an 8-byte SPP.
    SECTION("exact") {
        REQUIRE(link_src.dsize() == 16);
        CHECK(satcat5::test::write(&srcp, make_spp(0, "Test1234")));
        CHECK(satcat5::test::write(&srcp, make_spp(1, "Half")));
        CHECK(satcat5::test::write(&srcp, make_spp(2, "MoreData")));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&dstp, make_spp(0, "Test1234")));
        CHECK(satcat5::test::read(&dstp, make_spp(1, "Half")));
        CHECK(satcat5::test::read(&dstp, make_spp(2, "MoreData")));
    }

    // Test premable synchronziation from an unaligned stream.
    constexpr u8 STRM[] = {
        0x40, 0x00, 0x00, 0x06, 0x53, 0x65, 0x76, 0x65, 0x72, 0x61, 0x6C, 0x11, 0x77, 0x44,
        0x1A, 0xCF, 0xFC, 0x1D, 0x4A, 0xAC, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x11, 0x23,
        0xC0, 0x00, 0x00, 0x02, 0x50, 0x6B, 0x74, 0x07, 0xFF, 0x40, 0x00, 0x00, 0x8B, 0x08};

    SECTION("sync") {
        CHECK(satcat5::test::write(&phy_rx, sizeof(STRM), STRM));
        satcat5::poll::service_all();
        CHECK(satcat5::test::read(&dstp, make_spp(0, "Pkt")));
    }
}
