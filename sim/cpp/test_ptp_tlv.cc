//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the "ptp::TlvHandler" and "ptp::TlvHeader" classes.

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ptp_header.h>
#include <satcat5/ptp_measurement.h>
#include <satcat5/ptp_time.h>
#include <satcat5/ptp_tlv.h>

using satcat5::io::LimitedRead;
using satcat5::ptp::HEADER_NULL;
using satcat5::ptp::TlvHandler;
using satcat5::ptp::TlvHeader;
using satcat5::test::write_random_bytes;

// PTP and TLV headers used in various tests.
static const TlvHeader TEST_HDR1 =
    {satcat5::ptp::TLVTYPE_MANAGEMENT, 32, 0, 0};
static const TlvHeader TEST_HDR2 =
    {satcat5::ptp::TLVTYPE_ORG_EXT_NP, 4, 0x123456, 0x789ABC};
static const TlvHeader TEST_HDR3 =
    {satcat5::ptp::TLVTYPE_ORG_EXT_P, 0, 0xDEADBE, 0xEFCAFE};

// Helper objects for testing TlvHandler methods.
class TlvReadOnly : public TlvHandler {
public:
    TlvReadOnly() : TlvHandler(0) {}

    // Override "tlv_rcvd" and default "tlv_send".
    bool tlv_rcvd(
        const satcat5::ptp::Header& hdr,
        const satcat5::ptp::TlvHeader& tlv,
        satcat5::io::LimitedRead& rd) override
    {
        // Match HDR1 only, ignore other TLV types.
        if (tlv.match(TEST_HDR1)) {
            rd.read_consume(tlv.length);
            return true;
        } else {
            return false;
        }
    }
};

class TlvWriteOnly : public TlvHandler {
public:
    TlvWriteOnly() : TlvHandler(0) {}

    // Default "tlv_rcvd" and override "tlv_send".
    unsigned tlv_send(
        const satcat5::ptp::Header& hdr,
        satcat5::io::Writeable* wr) override
    {
        // Write three complete tags filled with random data.
        if (wr) {
            wr->write_obj(TEST_HDR1);
            write_random_bytes(wr, TEST_HDR1.length);
            wr->write_obj(TEST_HDR2);
            write_random_bytes(wr, TEST_HDR2.length);
            wr->write_obj(TEST_HDR3);
            write_random_bytes(wr, TEST_HDR3.length);
        }
        return TEST_HDR1.len_total()
             + TEST_HDR2.len_total()
             + TEST_HDR3.len_total();
    }

    // Override the default "tlv_meas" to modify one field.
    void tlv_meas(satcat5::ptp::Measurement& meas) override {
        meas.t4 += satcat5::ptp::ONE_SECOND;
    }
};

TEST_CASE("tlv_handler") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    satcat5::io::PacketBufferHeap buff;
    TlvReadOnly tlv_rd;
    TlvWriteOnly tlv_wr;

    // Basic test writes and reads three tags.
    SECTION("write_read") {
        // Give both handlers an opportunity to write.
        // (Callback in predict and write modes for each UUT.)
        unsigned wr1 = tlv_rd.tlv_send(HEADER_NULL, 0);
        unsigned wr2 = tlv_rd.tlv_send(HEADER_NULL, &buff);
        unsigned wr3 = tlv_wr.tlv_send(HEADER_NULL, 0);
        unsigned wr4 = tlv_wr.tlv_send(HEADER_NULL, &buff);
        REQUIRE(buff.write_finalize());
        CHECK(wr1 == 0);
        CHECK(wr2 == 0);
        CHECK(wr3 == wr4);
        CHECK(wr4 == buff.get_read_ready());
        // Parse the resulting byte-stream...
        TlvHeader tlv;
        unsigned count0 = 0, count1 = 0;
        while (tlv.read_from(&buff)) {
            // Create a limited-read object for the tag data.
            LimitedRead rd(&buff, tlv.length);
            // The write-only handler should never match.
            CHECK_FALSE(tlv_wr.tlv_rcvd(HEADER_NULL, tlv, rd));
            // The read-only handler should match one of three tags.
            if (tlv_rd.tlv_rcvd(HEADER_NULL, tlv, rd)) {
                ++count1;
            } else {
                ++count0;
            }
            // Read up to the next TLV tag.
            rd.read_finalize();
        }
        // Confirm matching tag counts match expectations.
        CHECK(count0 == 2);
        CHECK(count1 == 1);
    }

    // Test the default and modified "tlv_meas" event handlers.
    SECTION("measurement") {
        satcat5::ptp::Measurement meas = satcat5::ptp::MEASUREMENT_NULL;
        tlv_rd.tlv_meas(meas);
        CHECK(meas.t4 == satcat5::ptp::TIME_ZERO);
        tlv_wr.tlv_meas(meas);
        CHECK(meas.t4 == satcat5::ptp::ONE_SECOND);
    }
}

TEST_CASE("tlv_header") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    SECTION("propagate") {
        CHECK_FALSE(TEST_HDR1.propagate());     // MANAGEMENT (Do not propagate)
        CHECK_FALSE(TEST_HDR2.propagate());     // ORGANIZATION_EXTENSION_DO_NOT_PROPAGATE
        CHECK      (TEST_HDR3.propagate());     // ORGANIZATION_EXTENSION_PROPAGATE
    }
}
