//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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
// Test cases for the SatCat5 on-demand polling system (polling.h)

#include <ctime>
#include <deque>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/polling.h>

namespace poll = satcat5::poll;
using satcat5::test::CountAlways;
using satcat5::test::CountOnDemand;
using satcat5::test::CountTimer;

TEST_CASE("polling") {
    SECTION("always") {
        // Set up three "Always" blocks and call service() a few times.
        CountAlways a, b, c;
        for (unsigned n = 0 ; n < 10 ; ++n)
            poll::service();
        // Confirm each block was called the expected number of times.
        // Note: One "extra" Always block for global OnDemandHelper.
        CHECK(poll::Always::count() == 4);
        CHECK(a.count() == 10);
        CHECK(b.count() == 10);
        CHECK(c.count() == 10);
    }

    SECTION("always-delete") {
        CountAlways *a = new CountAlways();
        CountAlways *b = new CountAlways();
        CountAlways *c = new CountAlways();
        CHECK(poll::Always::count() == 4);
        delete b;
        delete a;
        delete c;
        CHECK(poll::Always::count() == 1);
    }

    SECTION("ondemand") {
        // On-demand polling interleaved calls to main service loop.
        CountOnDemand a, b, c;
        for (unsigned n = 0 ; n < 10 ; ++n) {
            poll::service();
            if (n == 3) a.request_poll();
            if (n == 5) b.request_poll();
            if (n == 1 || n == 7) c.request_poll();
            if (n == 7) c.request_poll();   // Double-request
        }
        // Confirm each block was called the expected number of times,
        // and that there are no outstanding requests in the queue.
        CHECK(poll::OnDemand::count() == 0);
        CHECK(a.count() == 1);
        CHECK(b.count() == 1);
        CHECK(c.count() == 2);
    }

    SECTION("ondemand-delete") {
        CountOnDemand *a = new CountOnDemand();
        CountOnDemand *b = new CountOnDemand();
        CountOnDemand *c = new CountOnDemand();
        CHECK(poll::OnDemand::count() == 0);
        a->request_poll();
        b->request_poll();
        CHECK(poll::OnDemand::count() == 2);
        delete a;   // Active
        delete b;   // Active
        delete c;   // Inactive
        CHECK(poll::OnDemand::count() == 0);
    }

    SECTION("timer") {
        // Set up three Timer objects.
        CountTimer a, b, c;
        a.timer_once(3);    // 3 only
        b.timer_every(3);   // 3, 6, 9
        c.timer_every(2);   // 2, 4 (stop early)
        // Update the global Timekeeper object a few times.
        for (unsigned n = 0 ; n < 10 ; ++n) {
            poll::service();
            if (n == 5) c.timer_stop();
            poll::timekeeper.request_poll();
        }
        // Confirm expected event counts.
        CHECK(poll::Timer::count() == 3);
        CHECK(a.count() == 1);
        CHECK(b.count() == 3);
        CHECK(c.count() == 2);
    }

    SECTION("timer-adapter") {
        // Link a TimerAdapter to a CountOnDemand object.
        CountOnDemand ctr;
        poll::TimerAdapter uut(&ctr);
        uut.timer_every(3);
        // Update the global Timekeeper object a few times.
        for (unsigned n = 0 ; n < 10 ; ++n) {
            poll::service();
            poll::timekeeper.request_poll();
        }
        // Confirm expected event counts.
        CHECK(ctr.count() == 3);
    }

    SECTION("timer-delete") {
        CountTimer *a = new CountTimer();
        CountTimer *b = new CountTimer();
        CountTimer *c = new CountTimer();
        CHECK(poll::Timer::count() == 3);
        delete b;
        delete a;
        delete c;
        CHECK(poll::Timer::count() == 0);
    }

    SECTION("virtual-timer") {
        // Create a 100 Hz virtual-timer object linked to system time.
        CountOnDemand ctr;
        satcat5::util::PosixTimer timer;
        satcat5::irq::VirtualTimer uut(&ctr, &timer, 10000);
        // Run the polling loop for ~100 msec (1/10th second)
        clock_t start    = clock();
        clock_t duration = CLOCKS_PER_SEC / 10;
        while (clock() - start < duration) {
            poll::service();
        }
        // Confirm we got roughly the expected event count.
        // Note: This assumes timer resolution <= 10 msec.
        CHECK(ctr.count() >=  8);
        CHECK(ctr.count() <= 12);
    }

}
