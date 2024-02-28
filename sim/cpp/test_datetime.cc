// //////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for real-time clock conversion functions

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/datetime.h>
#include <satcat5/io_core.h>

using satcat5::datetime::GpsTime;
using satcat5::datetime::RtcTime;
using satcat5::datetime::from_gps;
using satcat5::datetime::from_ptp;
using satcat5::datetime::from_rtc;
using satcat5::datetime::to_gps;
using satcat5::datetime::to_ptp;
using satcat5::datetime::to_rtc;
using satcat5::datetime::RTC_ERROR;
using satcat5::datetime::TIME_ERROR;
typedef satcat5::ptp::Time PtpTime;

// Direct access for functions that aren't in the public API.
extern u8 bcd_convert_24hr(u8 val);

// Note: Input is in quasi-GPS "timezone", no leap seconds.
static RtcTime make_rtc(
    unsigned dw,        // Day of week (0-6, 0 = Sunday)
    unsigned yr,        // Year (00-99)
    unsigned mo,        // Month (1-12)
    unsigned dt,        // Day-of-month (1-31)
    unsigned hr,        // Hour (0-23)
    unsigned mn,        // Minutes (0-59)
    unsigned sc,        // Seconds (0-59)
    unsigned ss = 0)    // Sub-seconds (0-99)
{
    return RtcTime {
        (u8)dw, (u8)yr, (u8)mo, (u8)dt,
        (u8)hr, (u8)mn, (u8)sc, (u8)ss};
}

static RtcTime make_rtc(const u8* bytes)
{
    satcat5::io::ArrayRead buff(bytes, 8);
    RtcTime rtc;
    CHECK(buff.read_obj(rtc));
    return rtc;
}

static bool attempt_read(const u8* bytes)
{
    satcat5::io::ArrayRead buff(bytes, 8);
    RtcTime rtc;
    bool ok = buff.read_obj(rtc);
    if (!ok) CHECK(rtc == RTC_ERROR);
    return ok;
}

static void check_equivalent(
    const RtcTime& rtc_ref,
    const GpsTime& gps_ref)
{
    // Convert each reference to the opposing format.
    GpsTime gps_uut = to_gps(from_rtc(rtc_ref));
    RtcTime rtc_uut = to_rtc(from_gps(gps_ref));

    // Check that converted RTC->GPS time matches GPS reference.
    CHECK(gps_uut.wkn == gps_ref.wkn);
    CHECK(gps_uut.tow == gps_ref.tow);
    CHECK(gps_uut == gps_ref);

    // Check that converted GPS->RTC time matches RTC reference.
    // (Note: Normalize both "hours" fields to 24-hour time.)
    CHECK(rtc_uut.dw == rtc_ref.dw);
    CHECK(rtc_uut.yr == rtc_ref.yr);
    CHECK(rtc_uut.mo == rtc_ref.mo);
    CHECK(rtc_uut.dt == rtc_ref.dt);
    CHECK(rtc_uut.hr == rtc_ref.hr);
    CHECK(rtc_uut.mn == rtc_ref.mn);
    CHECK(rtc_uut.sc == rtc_ref.sc);
    CHECK(rtc_uut.ss == rtc_ref.ss);
    CHECK(rtc_uut == rtc_ref);
}

static void check_equivalent(
    const PtpTime& ptp_ref,
    const GpsTime& gps_ref)
{
    GpsTime gps_uut = to_gps(from_ptp(ptp_ref));
    PtpTime ptp_uut = to_ptp(from_gps(gps_ref));

    // Check that converted PTP->GPS time matches GPS reference.
    CHECK(gps_uut.wkn == gps_ref.wkn);
    CHECK(gps_uut.tow == gps_ref.tow);
    CHECK(gps_uut == gps_ref);

    // Check that converted GPS->PTP time matches PTP reference.
    CHECK(ptp_uut.field_secs() == ptp_ref.field_secs());
    CHECK(ptp_uut.field_nsec() == ptp_ref.field_nsec());
    CHECK(ptp_uut == ptp_ref);
}

u64 gps_seconds(const GpsTime& gps)
{
    return u64(7 * 86400 * gps.wkn + gps.tow / 1000);
}

TEST_CASE("DateTime-Clock") {
    satcat5::util::PosixTimer timer;
    satcat5::irq::VirtualTimer(&satcat5::poll::timekeeper, &timer);
    satcat5::datetime::Clock uut(&timer);

    // Set absolute start time = 1234 msec (arbitrary)
    uut.set(1234);
    u32 tref = timer.now();

    // Wait 50 msec...
    while (timer.elapsed_usec(tref) < 50000) {
        satcat5::poll::timekeeper.request_poll();
        satcat5::poll::service();        // Wait 50 msec...
    }
    CHECK(uut.now() >= 1279);   // Expect 1284 +/- 5 msec
    CHECK(uut.now() <= 1289);

    // Wait another 50 msec...
    while (timer.elapsed_usec(tref) < 100000) {
        satcat5::poll::timekeeper.request_poll();
        satcat5::poll::service();        // Wait 100 msec...
    }
    CHECK(uut.now() >= 1329);   // Expect 1334 +/- 5 msec
    CHECK(uut.now() <= 1339);
}

TEST_CASE("DateTime-Conversions") {
    // Test each of the following pairs.
    // To make more, use the following tool with leap-seconds set to zero:
    //  https://www.labsat.co.uk/index.php/en/gps-time-calculator
    SECTION("Convert 2020-11-11T17:00:00 (Wednesday)") {
        RtcTime rtc = make_rtc(3, 20, 11, 11, 17, 0, 0);
        GpsTime gps = {2131, 320400000};
        check_equivalent(rtc, gps);
        CHECK(rtc.days_since_epoch() == 7620);
        CHECK(rtc.msec_since_midnight() == 61200000);
    }
    SECTION("Convert 2000-01-02T05:00:00 (Sunday)") {
        RtcTime rtc = make_rtc(0, 0, 1, 2, 5, 0, 0);
        GpsTime gps = {1043, 18000000};
        check_equivalent(rtc, gps);
    }
    SECTION("Convert 2001-01-02T02:00:00 (Tuesday)") {
        RtcTime rtc = make_rtc(2, 1, 1, 2, 2, 0, 0);
        GpsTime gps = {1095, 180000000};
        check_equivalent(rtc, gps);
        CHECK(rtc.days_since_epoch() == 367);
        CHECK(rtc.msec_since_midnight() == 7200000);
    }
    SECTION("Convert 2000-02-29T05:00:00 (Tuesday)") {
        RtcTime rtc = make_rtc(2, 0, 2, 29, 5, 0, 0);
        GpsTime gps = {1051, 190800000};
        check_equivalent(rtc, gps);
    }
    SECTION("Convert 2000-01-01T00:00:00 (Saturday)") {
        RtcTime rtc = make_rtc(6, 0, 1, 1, 0, 0, 0);
        GpsTime gps = {1042, 518400000};
        check_equivalent(rtc, gps);
    }
    SECTION("Convert 2016-04-08T00:00:00 (Friday)") {
        RtcTime rtc = make_rtc(5, 16, 4, 8, 0, 0, 0);
        GpsTime gps = {1891, 432000000};
        check_equivalent(rtc, gps);
        CHECK(rtc.days_since_epoch() == 5942);
        CHECK(rtc.msec_since_midnight() == 0);
    }

    // Check specific rollover events are calculated correctly.
    SECTION("Difference 2020-05-12T22:00:00 (Sunday)") {
        s64 tick0 = from_rtc(make_rtc(0, 20, 5, 12, 21, 59, 23));
        s64 tick1 = from_rtc(make_rtc(0, 20, 5, 12, 21, 59, 59));
        s64 tick2 = from_rtc(make_rtc(0, 20, 5, 12, 22, 00, 01));
        CHECK(tick1 - tick0 == 36000);
        CHECK(tick2 - tick0 == 38000);
    }

    // PTP conversions follow guidance from IEEE1588-2019 Section B.3.
    SECTION("PTP Conversions") {
        const u64 GPS_OFFSET = 315964819;
        GpsTime gps1 = {1042, 518400000};
        GpsTime gps2 = {1891, 432000000};
        satcat5::ptp::Time ptp1(gps_seconds(gps1) + GPS_OFFSET, 0, 0);
        satcat5::ptp::Time ptp2(gps_seconds(gps2) + GPS_OFFSET, 0, 0);
        check_equivalent(ptp1, gps1);
        check_equivalent(ptp2, gps2);
    }

    // Check various off-nominal RTC strings.
    SECTION("RtcString-NoMIL") {
        // Define preset times that using AM/PM notation (PM = 0x20)
        //                   SS    SC    MN    HR    DT    MO    YR    DW
        const u8 str1[] = {0x00, 0x00, 0x00, 0x12, 0x26, 0x12, 0x21, 0x00};  // 12am (00:00)
        const u8 str2[] = {0x00, 0x00, 0x00, 0x06, 0x26, 0x12, 0x21, 0x00};  //  6am (06:00)
        const u8 str3[] = {0x00, 0x00, 0x00, 0x32, 0x26, 0x12, 0x21, 0x00};  // 12pm (12:00)
        const u8 str4[] = {0x00, 0x00, 0x00, 0x26, 0x26, 0x12, 0x21, 0x00};  //  6pm (18:00)
        const u8 str5[] = {0x98, 0x59, 0x59, 0x31, 0x26, 0x12, 0x21, 0x00};  // Almost midnight
        const u8 str6[] = {0x99, 0x59, 0x59, 0x31, 0x26, 0x12, 0x21, 0x00};  // Almost midnight
        RtcTime rtc1 = make_rtc(str1);
        RtcTime rtc2 = make_rtc(str2);
        RtcTime rtc3 = make_rtc(str3);
        RtcTime rtc4 = make_rtc(str4);
        RtcTime rtc5 = make_rtc(str5);
        RtcTime rtc6 = make_rtc(str6);
        GpsTime gps1 = {2190, 0};         // 12am (00:00)
        GpsTime gps2 = {2190, 21600000};  //  6am (06:00)
        GpsTime gps3 = {2190, 43200000};  // 12pm (12:00)
        GpsTime gps4 = {2190, 64800000};  //  6pm (18:00)
        GpsTime gps5 = {2190, 86399980};  // Almost midnight
        GpsTime gps6 = {2190, 86399990};  // Almost midnight
        check_equivalent(rtc1, gps1);
        check_equivalent(rtc2, gps2);
        check_equivalent(rtc3, gps3);
        check_equivalent(rtc4, gps4);
        check_equivalent(rtc5, gps5);
        check_equivalent(rtc6, gps6);
        // While we're here, check the comparison operators.
        CHECK(rtc1 < rtc2);
        CHECK(gps1 < gps2);
        CHECK(rtc5 < rtc6);
        CHECK(gps5 < gps6);
        CHECK_FALSE(rtc2 < rtc1);
        CHECK_FALSE(gps2 < gps1);
        CHECK_FALSE(rtc6 < rtc5);
        CHECK_FALSE(gps6 < gps5);
    }

    SECTION("RtcString-Months") {
        // Check last valid day for month 1-12 (Jan - Dec) on 2016, which is a leap year.
        RtcTime rtc = make_rtc(0, 16, 1, 0, 23, 59, 59, 99);
        const u8 lastday[]  = {31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
        for (unsigned m = 0 ; m < 12 ; ++m) {
            rtc.mo = m + 1;
            rtc.dt = lastday[m];        // Last valid day
            CHECK(from_rtc(rtc) != TIME_ERROR);
            rtc.dt = lastday[m] + 1;    // First invalid day
            CHECK(from_rtc(rtc) == TIME_ERROR);
        }
        // One last check on a non-leap year.
        rtc.yr = 17; rtc.mo = 2; rtc.dt = 28;
        CHECK(from_rtc(rtc) != TIME_ERROR);
        rtc.yr = 17; rtc.mo = 2; rtc.dt = 29;
        CHECK(from_rtc(rtc) == TIME_ERROR);
    }

    SECTION("RtcString-Invalid") {
        //                   SS    SC    MN    HR    DT    MO    YR    DW
        const u8 str0[] = {0x99, 0x59, 0x59, 0x23, 0x31, 0x12, 0x9A, 0x00};
        const u8 str1[] = {0x99, 0x59, 0x59, 0x23, 0x31, 0x13, 0x99, 0x00};
        const u8 str2[] = {0x99, 0x59, 0x59, 0xA4, 0x31, 0x12, 0x99, 0x00};
        const u8 str3[] = {0x99, 0x59, 0x60, 0x23, 0x31, 0x12, 0x99, 0x00};
        const u8 str4[] = {0x99, 0x60, 0x59, 0x23, 0x31, 0x12, 0x99, 0x00};
        const u8 str5[] = {0x9A, 0x59, 0x59, 0x23, 0x31, 0x12, 0x99, 0x00};
        CHECK_FALSE(attempt_read(str0));
        CHECK_FALSE(attempt_read(str1));
        CHECK_FALSE(attempt_read(str2));
        CHECK_FALSE(attempt_read(str3));
        CHECK_FALSE(attempt_read(str4));
        CHECK_FALSE(attempt_read(str5));
    }

    // Out-of-range date conversions (RTC only covers year 2000 - 2099)
    SECTION("RtcString-Range") {
        s64 too_early = from_gps(GpsTime {1042, 518399000});  // 1999 Dec 31
        s64 too_late  = from_gps(GpsTime {6260, 432000000});  // 2100 Jan 01
        CHECK(to_rtc(too_early) == RTC_ERROR);
        CHECK(to_rtc(too_late) == RTC_ERROR);
    }

    // I/O functions.
    SECTION("GPS-Read") {
        satcat5::io::PacketBufferHeap buff;
        buff.write_u32(4247);       // Week#
        buff.write_u32(12345678);   // TOW
        buff.write_u16(4321);       // (Not enough bytes)
        buff.write_finalize();
        GpsTime rd1, rd2;
        CHECK(buff.read_obj(rd1));  // Should succeed
        CHECK(!buff.read_obj(rd2)); // Should underflow
        CHECK(rd1.wkn == 4247);
        CHECK(rd1.tow == 12345678);
    }
    SECTION("GPS-Write") {
        satcat5::io::PacketBufferHeap buff;
        GpsTime ref = {1234, 5678};
        buff.write_obj(ref);
        buff.write_finalize();
        CHECK(buff.read_u32() == 1234);
        CHECK(buff.read_u32() == 5678);
    }
    SECTION("RTC-Read") {
        satcat5::io::PacketBufferHeap buff;
        buff.write_u32(0x00000097); // Include MIL flag
        buff.write_u32(0x11112003);
        buff.write_finalize();
        RtcTime uut, ref = make_rtc(3, 20, 11, 11, 17, 0, 0);
        CHECK(buff.read_obj(uut));
        CHECK(uut == ref);
    }
    SECTION("RTC-Write") {
        satcat5::io::PacketBufferHeap buff;
        RtcTime ref = make_rtc(3, 20, 11, 11, 17, 0, 0);
        buff.write_obj(ref);
        buff.write_finalize();
        CHECK(buff.read_u32() == 0x00000097);   // Include MIL flag
        CHECK(buff.read_u32() == 0x11112003);
    }
}

TEST_CASE("DateTime-Internal") {
    SECTION("bcd_convert") {
        // 24-hour time (MIL flag = 0x80)
        CHECK(bcd_convert_24hr(0x80) == 0);
        CHECK(bcd_convert_24hr(0x86) == 6);
        CHECK(bcd_convert_24hr(0x92) == 12);
        CHECK(bcd_convert_24hr(0xA3) == 23);
        // 12-hour time (PM flag = 0x20)
        CHECK(bcd_convert_24hr(0x12) == 0);     // 12 AM = 00:00 (midnight)
        CHECK(bcd_convert_24hr(0x01) == 1);     //  1 AM
        CHECK(bcd_convert_24hr(0x02) == 2);     //  2 AM
        CHECK(bcd_convert_24hr(0x03) == 3);     //  3 AM
        CHECK(bcd_convert_24hr(0x04) == 4);     //  4 AM
        CHECK(bcd_convert_24hr(0x05) == 5);     //  5 AM
        CHECK(bcd_convert_24hr(0x06) == 6);     //  6 AM
        CHECK(bcd_convert_24hr(0x07) == 7);     //  7 AM
        CHECK(bcd_convert_24hr(0x08) == 8);     //  8 AM
        CHECK(bcd_convert_24hr(0x09) == 9);     //  9 AM
        CHECK(bcd_convert_24hr(0x10) == 10);    // 10 AM
        CHECK(bcd_convert_24hr(0x11) == 11);    // 11 AM
        CHECK(bcd_convert_24hr(0x32) == 12);    // 12 PM = 12:00 (noon)
        CHECK(bcd_convert_24hr(0x21) == 13);    //  1 PM
        CHECK(bcd_convert_24hr(0x22) == 14);    //  2 PM
        CHECK(bcd_convert_24hr(0x23) == 15);    //  3 PM
        CHECK(bcd_convert_24hr(0x24) == 16);    //  4 PM
        CHECK(bcd_convert_24hr(0x25) == 17);    //  5 PM
        CHECK(bcd_convert_24hr(0x26) == 18);    //  6 PM
        CHECK(bcd_convert_24hr(0x27) == 19);    //  7 PM
        CHECK(bcd_convert_24hr(0x28) == 20);    //  8 PM
        CHECK(bcd_convert_24hr(0x29) == 21);    //  9 PM
        CHECK(bcd_convert_24hr(0x30) == 22);    //  10 PM
        CHECK(bcd_convert_24hr(0x31) == 23);    //  11 PM
        // Invalid BCD timestamps.
        CHECK(bcd_convert_24hr(0x13) == 0xFF);  // 13 AM = Invalid
        CHECK(bcd_convert_24hr(0x33) == 0xFF);  // 13 PM = Invalid
    }
}
