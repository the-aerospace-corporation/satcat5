//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the "ntp::Client" class

#include <hal_test/catch.hpp>
#include <hal_test/eth_crosslink.h>
#include <hal_test/ptp_simclock.h>
#include <hal_test/sim_utils.h>
#include <satcat5/datetime.h>
#include <satcat5/ip_stack.h>
#include <satcat5/ntp_client.h>

using satcat5::datetime::from_gps;
using satcat5::datetime::from_ptp;
using satcat5::datetime::to_ptp;
using satcat5::datetime::GpsTime;
using satcat5::ntp::Client;
using satcat5::ntp::Header;
using satcat5::test::CountPtpCallback;
using satcat5::udp::PORT_NTP_SERVER;

// NTPv3 captures from Wireshark examples:
// https://wiki.wireshark.org/uploads/__moin_import__/attachments/SampleCaptures/NTP_sync.pcap
static const u8 NTP_QUERY[] = {
    0xD9, 0x00, 0x0A, 0xFA, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x90,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0xC5, 0x02, 0x04, 0xEC, 0xEC, 0x42, 0xEE, 0x92};
static const u8 NTP_REPLY[] = {
    0x1A, 0x03, 0x0A, 0xEE, 0x00, 0x00, 0x1B, 0xF7, 0x00, 0x00, 0x14, 0xEC,
    0x51, 0xAE, 0x80, 0xB7, 0xC5, 0x02, 0x03, 0x4C, 0x8D, 0x0E, 0x66, 0xCB,
    0xC5, 0x02, 0x04, 0xEC, 0xEC, 0x42, 0xEE, 0x92, 0xC5, 0x02, 0x04, 0xEB,
    0xCF, 0x49, 0x59, 0xE6, 0xC5, 0x02, 0x04, 0xEB, 0xCF, 0x4C, 0x6E, 0x6D};

// Example of a kiss-of-death packet ("DENY").
static const u8 NTP_DENY[] = {
    0x1C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x44, 0x45, 0x4E, 0x59, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

TEST_CASE("ntp_client") {
    // Simulation infrastructure
    SATCAT5_TEST_START;
    satcat5::ptp::SimulatedClock clk0(100e6, 100e6);
    satcat5::ptp::SimulatedClock clk1(125e6, 125e6);
    satcat5::test::CrosslinkIp xlink(__FILE__);

    // Two back-to-back NTP clients.
    Client uut0(&clk0, &xlink.net0.m_udp);
    Client uut1(&clk1, &xlink.net1.m_udp);
    CountPtpCallback count0(&uut0);
    CountPtpCallback count1(&uut1);

    // A connected client and server should complete time-transfer handshakes.
    SECTION("basic") {
        // Start server and client, then let some time elapse.
        uut0.server_start(1);
        uut1.client_connect(xlink.IP0, Header::TIME_1SEC);
        xlink.timer.sim_wait(5000);
        // Confirm client completed at least one handshake.
        CHECK(uut1.client_ok());
        CHECK(count0.count() == 0);
        CHECK(count1.count() > 0);
        // Cleanup.
        uut1.client_close();
    }

    // A connected client that receives a DENY message should disconnect.
    SECTION("deny") {
        // Start server and client, then let some time elapse.
        uut0.server_start(1);
        uut1.client_connect(xlink.IP0, Header::TIME_1SEC);
        xlink.timer.sim_wait(2000);
        // Once a connection is established, shut down the server.
        CHECK(uut1.client_ok());
        uut0.server_start(1);
        // Inject a DENY message as a fake "reply" from the server.
        satcat5::udp::Address udp(&xlink.net0.m_udp);
        udp.connect(xlink.IP1, xlink.MAC1, PORT_NTP_SERVER, PORT_NTP_SERVER);
        auto wr = udp.open_write(sizeof(NTP_DENY));
        REQUIRE(wr != 0);
        wr->write_bytes(sizeof(NTP_DENY), NTP_DENY);
        CHECK(wr->write_finalize());
        // After the DENY message is received, the client should disconnect.
        xlink.timer.sim_wait(1000);
        CHECK_FALSE(uut1.client_ok());
    }

    // Timestamp format conversions should operate normally through NTP rollover.
    SECTION("conversion") {
        // Define some constants in the SatCat5 datetime format.
        const s64 ref0_msec = from_gps(GpsTime({1042, 519418}));    // Y2K rollover  (1999 Dec 31)
        const s64 ref1_msec = from_gps(GpsTime({2318, 488894}));    // Typical date  (2024 Jun 14)
        const s64 ref2_msec = from_gps(GpsTime({2926, 368896}));    // NTP rollover  (2036 Feb 07)
        const s64 ref3_msec = from_gps(GpsTime({2928, 196096}));    // Post rollover (2036 Feb 19)
        // Set system time to 2024 and convert some dates.
        clk0.clock_set(to_ptp(ref1_msec));
        s64 time0_ntp = uut0.to_ntp(to_ptp(ref0_msec));
        s64 time1_ntp = uut0.to_ntp(to_ptp(ref1_msec));
        s64 time2_ntp = uut0.to_ntp(to_ptp(ref2_msec));
        s64 time3_ntp = uut0.to_ntp(to_ptp(ref3_msec));
        s64 time0_msec = from_ptp(uut0.to_ptp(time0_ntp));
        s64 time1_msec = from_ptp(uut0.to_ptp(time1_ntp));
        s64 time2_msec = from_ptp(uut0.to_ptp(time2_ntp));
        s64 time3_msec = from_ptp(uut0.to_ptp(time3_ntp));
        CHECK(abs(ref0_msec - time0_msec) <= 1);
        CHECK(abs(ref1_msec - time1_msec) <= 1);
        CHECK(abs(ref2_msec - time2_msec) <= 1);
        CHECK(abs(ref3_msec - time3_msec) <= 1);
        // Set system time to 2036 and repeat the test.
        clk0.clock_set(to_ptp(ref3_msec));
        s64 time4_ntp = uut0.to_ntp(to_ptp(ref0_msec));
        s64 time5_ntp = uut0.to_ntp(to_ptp(ref1_msec));
        s64 time6_ntp = uut0.to_ntp(to_ptp(ref2_msec));
        s64 time7_ntp = uut0.to_ntp(to_ptp(ref3_msec));
        s64 time4_msec = from_ptp(uut0.to_ptp(time4_ntp));
        s64 time5_msec = from_ptp(uut0.to_ptp(time5_ntp));
        s64 time6_msec = from_ptp(uut0.to_ptp(time6_ntp));
        s64 time7_msec = from_ptp(uut0.to_ptp(time7_ntp));
        CHECK(abs(ref0_msec - time4_msec) <= 1);
        CHECK(abs(ref1_msec - time5_msec) <= 1);
        CHECK(abs(ref2_msec - time6_msec) <= 1);
        CHECK(abs(ref3_msec - time7_msec) <= 1);
    }
}

TEST_CASE("ntp_header") {
    satcat5::log::ToConsole log;
    satcat5::io::ArrayRead ntp_query(NTP_QUERY, sizeof(NTP_QUERY));
    satcat5::io::ArrayRead ntp_reply(NTP_REPLY, sizeof(NTP_REPLY));

    Header uut;

    // Logging an NTP header should output specific fields.
    SECTION("read-log") {
        // Read one of the example messages.
        CHECK(uut.read_from(&ntp_reply));
        // Spot-checks of the formatted log output.
        log.suppress("Log formatting test");
        satcat5::log::Log(satcat5::log::INFO, "Log formatting test").write_obj(uut);
        CHECK(log.contains("LI:      0"));
        CHECK(log.contains("VN:      3"));
        CHECK(log.contains("Mode:    2"));
        CHECK(log.contains("Stratum: 3"));
        CHECK(log.contains("RefID:   0x51AE80B7"));
    }

    // After reading an NTP header, writing it should produce the same bytes.
    SECTION("read-write") {
        // Read one of the example messages.
        CHECK(uut.read_from(&ntp_query));
        ntp_query.read_finalize();
        // Write the parsed structure back to a working buffer.
        satcat5::io::PacketBufferHeap tmp;
        tmp.write_obj(uut);
        tmp.write_finalize();
        // Confirm output matches the original reference.
        CHECK(satcat5::test::read_equal(&tmp, &ntp_query));
    }

    // Attempting to read a partial NTP header should produce an error.
    SECTION("read-fail") {
        // Truncate second half of one of the example captures.
        satcat5::io::ArrayRead half_query(NTP_QUERY, sizeof(NTP_QUERY) / 2);
        CHECK_FALSE(uut.read_from(&half_query));
    }
}
