//////////////////////////////////////////////////////////////////////////
// Copyright 2022, 2023 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// Test cases for the "ptp::Time" class

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/ptp_time.h>

using satcat5::ptp::MSEC_PER_SEC;
using satcat5::ptp::USEC_PER_SEC;
using satcat5::ptp::NSEC_PER_SEC;
using satcat5::ptp::SUBNS_PER_SEC;
using satcat5::ptp::SUBNS_PER_NSEC;
using satcat5::ptp::Time;
using satcat5::ptp::from_datetime;

TEST_CASE("ptp_time") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    SECTION("Constructors") {
        Time t1(12345);         // Subnanoseconds
        CHECK(t1.secs() == 0);
        CHECK(t1.subns() == 12345);
        CHECK(t1.delta_subns() == 12345);

        Time t2(-12345);        // Subnanoseconds
        CHECK(t2.secs() == -1);
        CHECK(t2.subns() == SUBNS_PER_SEC - 12345);
        CHECK(t2.delta_subns() == -12345);

        Time t3(12, 34567);     // Seconds + nanosec
        CHECK(t3.secs() == 12);
        CHECK(t3.nsec() == 34567);
        CHECK(t3.subns() == 34567 * SUBNS_PER_NSEC);
        CHECK(t3.delta_subns() == 786434265382912ll);

        Time t4(123, 456, 789); // Seconds + nanosec + subns
        CHECK(t4.secs() == 123);
        CHECK(t4.nsec() == 456);
        CHECK(t4.subns() == 456 * SUBNS_PER_NSEC + 789);
        CHECK(t4.delta_subns() == 8060928029885205ll);

        Time t5(t4);            // Copy constructor
        CHECK(t5 == t4);
        t5 = t3;                // Operator=
        CHECK(t5 == t3);
    }

    SECTION("Delta") {
        Time t1(1e5, 0);
        CHECK(t1.delta_msec() == 1e5 * MSEC_PER_SEC);
        CHECK(t1.delta_usec() == 1e5 * USEC_PER_SEC);
        CHECK(t1.delta_nsec() == 1e5 * NSEC_PER_SEC);
        CHECK(t1.delta_subns() == 1e5 * SUBNS_PER_SEC);
        CHECK((-t1).delta_nsec() == -1e5 * NSEC_PER_SEC);
        CHECK((-t1).delta_subns() == -1e5 * SUBNS_PER_SEC);

        Time t2(1e6, 0);
        CHECK(t2.delta_msec() == 1e6 * MSEC_PER_SEC);
        CHECK(t2.delta_usec() == 1e6 * USEC_PER_SEC);
        CHECK(t2.delta_nsec() == 1e6 * NSEC_PER_SEC);
        CHECK(t2.delta_subns() == INT64_MAX);
        CHECK((-t2).delta_nsec() == -1e6 * NSEC_PER_SEC);
        CHECK((-t2).delta_subns() == INT64_MIN);

        Time t3(1e10, 0);
        CHECK(t3.delta_msec() == 1e10 * MSEC_PER_SEC);
        CHECK(t3.delta_usec() == 1e10 * USEC_PER_SEC);
        CHECK(t3.delta_nsec() == INT64_MAX);
        CHECK(t3.delta_subns() == INT64_MAX);
        CHECK((-t3).delta_nsec() == INT64_MIN);
        CHECK((-t3).delta_subns() == INT64_MIN);

        Time t4(1, 234567890);
        CHECK(t4.delta_msec() == 1235ll);
        CHECK(t4.delta_usec() == 1234568ll);
        CHECK(t4.delta_nsec() == 1234567890ll);
        CHECK(t4.delta_subns() == 80908641239040ll);
    }

    SECTION("ReadFrom") {
        const u8 msg[] = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x12, 0x34, 0x56, 0x78};
        satcat5::io::ArrayRead rd1(msg, 10);    // Entire message (10 bytes)
        satcat5::io::ArrayRead rd2(msg, 7);     // Partial message (7 bytes)
        Time t(0);
        CHECK(t.read_from(&rd1));               // First read should succeed
        CHECK(t.secs() == 0x112233445566);
        CHECK(t.subns() == 0x123456780000);
        CHECK_FALSE(t.read_from(&rd2));         // Second read should fail
    }

    SECTION("WriteTo") {
        // Write data to working buffer.
        Time t(0x123456789ABCull, 0x11223344u);
        satcat5::io::PacketBufferHeap buf;
        buf.write_obj(t);
        buf.write_finalize();
        // Check result against reference.
        const u8 ref[] = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0x11, 0x22, 0x33, 0x44};
        CHECK(satcat5::test::read(&buf, sizeof(ref), ref));
    }

    SECTION("DateTime") {
        Time t1(315532819, 0);          // GPS epoch
        CHECK(t1.to_datetime() == 0);
        t1 += Time(SUBNS_PER_SEC);      // Add one second
        CHECK(t1.to_datetime() == 1000);

        Time t2 = from_datetime(2000);  // GPS epoch + 2 seconds
        CHECK(t2.to_datetime() == 2000);
        CHECK(t2.secs() == 315532821);
    }

    SECTION("Abs") {
        Time t1(1, 1);
        CHECK(t1.abs().delta_nsec() == 1000000001);
        CHECK((-t1).abs().delta_nsec() == 1000000001);

        Time t2(1, 0);
        CHECK(t2.abs().delta_nsec() == 1000000000);
        CHECK((-t2).abs().delta_nsec() == 1000000000);
    }

    SECTION("Addition") {
        Time t1(1, 123456789);
        Time t2(0, 999999999);

        Time t3 = t1 + t1;
        CHECK(t3.secs() == 2);
        CHECK(t3.nsec() == 246913578);
        CHECK(t3.delta_subns() == 147253728247808ll);

        Time t4 = t1 + t2;
        CHECK(t4.secs() == 2);
        CHECK(t4.nsec() == 123456788);
        CHECK(t4.delta_subns() == 139162864058368ll);

        Time t5 = t2 + t1;
        CHECK(t5.secs() == 2);
        CHECK(t5.nsec() == 123456788);
        CHECK(t5.delta_subns() == 139162864058368ll);

        Time t6 = t2 + t2;
        CHECK(t6.secs() == 1);
        CHECK(t6.nsec() == 999999998);
        CHECK(t6.delta_subns() == 131071999868928ll);
    }

    SECTION("Subtraction") {
        Time t1(1, 123456789);
        Time t2(0, 999999999);

        Time t3 = t1 - t1;
        CHECK(t3.secs() == 0);
        CHECK(t3.subns() == 0);
        CHECK(t3.delta_subns() == 0);

        Time t4 = t1 - t2;
        CHECK(t4.secs() == 0);
        CHECK(t4.nsec() == 123456790);
        CHECK(t4.delta_subns() == 8090864189440ll);

        Time t5 = t2 - t1;
        CHECK(t5.secs() == -1);
        CHECK(t5.nsec() == 876543210);
        CHECK(t5.delta_subns() == -8090864189440ll);

        Time t6 = t2 - t2;
        CHECK(t6.secs() == 0);
        CHECK(t6.subns() == 0);
        CHECK(t6.delta_subns() == 0);
    }

    SECTION("Multiplication") {
        Time t1(1, 123456789);
        Time t2(0, 999999999);

        Time t3 = t1 * 2;
        CHECK(t3.secs() == 2);
        CHECK(t3.nsec() == 246913578);
        CHECK(t3.delta_subns() == 147253728247808ll);

        Time t4 = t2 * 3;
        CHECK(t4.secs() == 2);
        CHECK(t4.nsec() == 999999997);
        CHECK(t4.delta_subns() == 196607999803392ll);

        Time t5 = t1 * 9 - t2 * 10;
        CHECK(t5.secs() == 0);
        CHECK(t5.nsec() == 111111111);
        CHECK(t5.delta_subns() == 7281777770496);
    }

    SECTION("Division") {
        Time t1(1, 123456789);
        Time t2(0, 999999999);

        Time t3 = (t1 + t2) / 2;
        CHECK(t3.secs() == 1);
        CHECK(t3.nsec() == 61728394);
        CHECK(t3.delta_subns() == 69581432029184ll);

        CHECK(t2 == (t2 * 10) / 10);
        CHECK(t2 == (t2 * 100) / 100);
        CHECK(t2 == (t2 * 1000) / 1000);
        CHECK(t2 == (t2 * 10000) / 10000);
    }

    SECTION("Comparison") {
        // Four constants: t1 > t2 > t3 > 54
        Time t1(1, 123456789);
        Time t2(0, 999999999);
        Time t3 = t1 - t2;
        Time t4 = t2 - t1;

        // Equality and complement
        CHECK      (t1 == t1);  CHECK_FALSE(t1 != t1);
        CHECK_FALSE(t1 == t2);  CHECK      (t1 != t2);
        CHECK_FALSE(t1 == t3);  CHECK      (t1 != t3);
        CHECK_FALSE(t1 == t4);  CHECK      (t1 != t4);
        CHECK_FALSE(t2 == t1);  CHECK      (t2 != t1);
        CHECK      (t2 == t2);  CHECK_FALSE(t2 != t2);
        CHECK_FALSE(t2 == t3);  CHECK      (t2 != t3);
        CHECK_FALSE(t2 == t4);  CHECK      (t2 != t4);
        CHECK_FALSE(t3 == t1);  CHECK      (t3 != t1);
        CHECK_FALSE(t3 == t2);  CHECK      (t3 != t2);
        CHECK      (t3 == t3);  CHECK_FALSE(t3 != t3);
        CHECK_FALSE(t3 == t4);  CHECK      (t3 != t4);
        CHECK_FALSE(t4 == t1);  CHECK      (t4 != t1);
        CHECK_FALSE(t4 == t2);  CHECK      (t4 != t2);
        CHECK_FALSE(t4 == t3);  CHECK      (t4 != t3);
        CHECK      (t4 == t4);  CHECK_FALSE(t4 != t4);

        // Less than and complement
        CHECK_FALSE(t1 < t1);   CHECK      (t1 >= t1);
        CHECK_FALSE(t1 < t2);   CHECK      (t1 >= t2);
        CHECK_FALSE(t1 < t3);   CHECK      (t1 >= t3);
        CHECK_FALSE(t1 < t4);   CHECK      (t1 >= t4);
        CHECK      (t2 < t1);   CHECK_FALSE(t2 >= t1);
        CHECK_FALSE(t2 < t2);   CHECK      (t2 >= t2);
        CHECK_FALSE(t2 < t3);   CHECK      (t2 >= t3);
        CHECK_FALSE(t2 < t4);   CHECK      (t2 >= t4);
        CHECK      (t3 < t1);   CHECK_FALSE(t3 >= t1);
        CHECK      (t3 < t2);   CHECK_FALSE(t3 >= t2);
        CHECK_FALSE(t3 < t3);   CHECK      (t3 >= t3);
        CHECK_FALSE(t3 < t4);   CHECK      (t3 >= t4);
        CHECK      (t4 < t1);   CHECK_FALSE(t4 >= t1);
        CHECK      (t4 < t2);   CHECK_FALSE(t4 >= t2);
        CHECK      (t4 < t3);   CHECK_FALSE(t4 >= t3);
        CHECK_FALSE(t4 < t4);   CHECK      (t4 >= t4);

        // Greater than and complement
        CHECK_FALSE(t1 > t1);   CHECK      (t1 <= t1);
        CHECK      (t1 > t2);   CHECK_FALSE(t1 <= t2);
        CHECK      (t1 > t3);   CHECK_FALSE(t1 <= t3);
        CHECK      (t1 > t4);   CHECK_FALSE(t1 <= t4);
        CHECK_FALSE(t2 > t1);   CHECK      (t2 <= t1);
        CHECK_FALSE(t2 > t2);   CHECK      (t2 <= t2);
        CHECK      (t2 > t3);   CHECK_FALSE(t2 <= t3);
        CHECK      (t2 > t4);   CHECK_FALSE(t2 <= t4);
        CHECK_FALSE(t3 > t1);   CHECK      (t3 <= t1);
        CHECK_FALSE(t3 > t2);   CHECK      (t3 <= t2);
        CHECK_FALSE(t3 > t3);   CHECK      (t3 <= t3);
        CHECK      (t3 > t4);   CHECK_FALSE(t3 <= t4);
        CHECK_FALSE(t4 > t1);   CHECK      (t4 <= t1);
        CHECK_FALSE(t4 > t2);   CHECK      (t4 <= t2);
        CHECK_FALSE(t4 > t3);   CHECK      (t4 <= t3);
        CHECK_FALSE(t4 > t4);   CHECK      (t4 <= t4);
    }

    SECTION("RandomArithmetic") {
        Catch::SimplePcg32 rng;
        for (unsigned iter = 0 ; iter < 100 ; ++iter) {
            // Generate a handful of random inputs.
            Time t1(rng() & 0xFFFF, rng());
            Time t2(rng() & 0xFFFF, rng());
            Time t3(rng() & 0xFFFF, rng());
            Time t4(rng() & 0xFFFF, rng());

            // Calculate sum/difference using methods under test.
            Time sum = t1 - t2 + t3 - t4;

            // Manually calculate normalized sum/difference and compare.
            s64 ref_secs  = t1.secs()  - t2.secs()  + t3.secs()  - t4.secs();
            s64 ref_subns = t1.subns() - t2.subns() + t3.subns() - t4.subns();
            s64 ref_delta = t1.delta_subns() - t2.delta_subns() + t3.delta_subns() - t4.delta_subns();
            while (ref_subns < 0)
                {ref_secs -= 1; ref_subns += SUBNS_PER_SEC;}
            while (ref_subns >= SUBNS_PER_SEC)
                {ref_secs += 1; ref_subns -= SUBNS_PER_SEC;}
            CHECK(sum.secs() == ref_secs);
            CHECK(sum.subns() == (u64)ref_subns);
            CHECK(sum.delta_subns() == ref_delta);
        }
    }
}
