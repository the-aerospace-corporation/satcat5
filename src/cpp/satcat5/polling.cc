//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
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

#include <satcat5/interrupts.h> // For AtomicLock
#include <satcat5/list.h>
#include <satcat5/polling.h>
#include <satcat5/timer.h>

namespace poll = satcat5::poll;
using satcat5::irq::AtomicLock;
using satcat5::util::GenericTimer;
using satcat5::util::ListCore;

// Global linked list for each major polling type:
// (Use of global pointer ensures this is initialized before any
//  individual object constructor, including other globals.)
static poll::Always*    g_list_always = 0;
static poll::OnDemand*  g_list_demand = 0;
static poll::Timer*     g_list_timer  = 0;

// Global helper object for Timers.
poll::Timekeeper poll::timekeeper;

// Human-readable label for AtomicLock.
static const char* const LBL_POLL = "POLL";

// Global helper object that services all on-demand children.
class poll::OnDemandHelper final : public poll::Always
{
public:
    // Constructor is the only public method.
    OnDemandHelper() : m_item(0) {}

private:
    // In rare cases, such as the wait loop of "cfgbus_remote", the
    // poll_always() method may be called recursively.  To avoid
    // leaving orphaned leftovers, retain the working pointer.
    poll::OnDemand *m_item;

    // Atomically claim the current global list, and create
    // an empty one in its place for future requests.
    inline void list_start() {
        AtomicLock lock(LBL_POLL);
        m_item = g_list_demand;
        g_list_demand = 0;
    }

    // Atomically pop the current item from the queue, updating
    // associated pointers and status flags to mark it as idle.
    inline poll::OnDemand* list_pop() {
        AtomicLock lock(LBL_POLL);
        poll::OnDemand* temp = m_item;
        m_item = m_item->m_next;
        temp->m_idle = 1;
        temp->m_next = 0;
        return temp;
    }

    // Poll each block on the "demand" list, resuming work in progress if
    // possible.  Reset the state of each item just before we process it.
    void poll_always() override {
        if (!m_item) list_start();
        while (m_item) {
            poll::OnDemand* next = list_pop();
            next->poll_demand();
        }
    }
} on_demand_helper;

void poll::service()
{
    // Poll each block on the global list exactly once.
    // (This includes the on_demand_helper defined above.)
    poll::Always* item = g_list_always;
    while (item) {
        item->poll_always();
        item = item->m_next;
    }
}

void poll::service_all(unsigned limit)
{
    // Always poll at least once.
    poll::service();

    // Continue until demand list is empty or iteration limit is reached.
    while (g_list_demand && limit) {
        poll::service();
        --limit;
    }
}

poll::Always::Always()
    : m_next(0)
{
    // Add this item to the head of the global list.
    AtomicLock lock(LBL_POLL);
    ListCore::add(g_list_always, this);
}

#if SATCAT5_ALLOW_DELETION
poll::Always::~Always()
{
    // Remove ourselves from the global linked list.
    AtomicLock lock(LBL_POLL);
    ListCore::remove(g_list_always, this);
}
#endif

unsigned poll::Always::count()
{
    AtomicLock lock(LBL_POLL);
    return ListCore::len(g_list_always);
}

poll::OnDemand::OnDemand()
    : m_next(0)
    , m_idle(1)
{
    // Nothing else to do at this time.
}

#if SATCAT5_ALLOW_DELETION
poll::OnDemand::~OnDemand()
{
    AtomicLock lock(LBL_POLL);

    // If we're idle, there's nothing else to do.
    if (m_idle) return;

    // Otherwise, remove ourselves from the global linked list.
    ListCore::remove(g_list_demand, this);
}
#endif

void poll::OnDemand::request_poll()
{
    // After safety-check, add this item to the head of the list.
    // (Re-adding an item creates an infinite loop in the linked-list.)
    AtomicLock lock(LBL_POLL);
    if (m_idle) {
        m_idle = 0;
        ListCore::add(g_list_demand, this);
    }
}

unsigned poll::OnDemand::count()
{
    AtomicLock lock(LBL_POLL);
    return ListCore::len(g_list_demand);
}

poll::Timekeeper::Timekeeper()
    : m_clock(0)
    , m_tref(0)
{
    // No other initialization required.
}

void poll::Timekeeper::set_clock(GenericTimer* timer)
{
    AtomicLock lock(LBL_POLL);
    m_clock = timer;
}

void poll::Timekeeper::poll_demand()
{
    // Measure elapsed time if a reference clock is available.
    unsigned elapsed_msec = 1;      // Default = 1 msec
    if (m_clock) {
        // Measure elapsed time since last call to "elapsed_msec".
        // ("m_tref" updated to m_clock->now(), less fractional leftovers.)
        AtomicLock lock(LBL_POLL);
        elapsed_msec = m_clock->elapsed_msec(m_tref);
        if (!elapsed_msec) return;  // Less than 1 msec elapsed?
    }
    // Check on each of the registered Timer objects.
    poll::Timer* item = g_list_timer;
    while(item) {
        item->query(elapsed_msec);
        item = item->m_next;
    }
}

poll::Timer::Timer()
    : m_next(0)
    , m_trem(0)
    , m_tnext(0)
{
    // Add this item to the head of the global list.
    AtomicLock lock(LBL_POLL);
    ListCore::add(g_list_timer, this);
}

#if SATCAT5_ALLOW_DELETION
poll::Timer::~Timer()
{
    // Remove ourselves from the global linked list.
    AtomicLock lock(LBL_POLL);
    ListCore::remove(g_list_timer, this);
}
#endif

unsigned poll::Timer::count()
{
    AtomicLock lock(LBL_POLL);
    return ListCore::len(g_list_timer);
}

void poll::Timer::timer_once(unsigned msec)
{
    m_trem  = msec;
    m_tnext = 0;
}

void poll::Timer::timer_every(unsigned msec)
{
    m_trem  = msec;
    m_tnext = msec;
}

void poll::Timer::timer_stop()
{
    m_trem  = 0;
    m_tnext = 0;
}

void poll::Timer::query(unsigned elapsed_msec)
{
    if (m_trem > elapsed_msec) {
        // Continue countdown...
        m_trem -= elapsed_msec;
    } else if (m_trem) {
        // Countdown just elapsed!
        timer_event();
        // Adjust next interval to minimize cumulative drift.
        // e.g., If timer scheduled every 1000 msec fires 5 msec late,
        // then next interval should be 995 msec to get back on schedule.
        // If overshoot is too large to fix, minimum delay is 1 msec.
        unsigned ovr = elapsed_msec - m_trem;
        if (m_tnext > ovr) {    // Adjust next interval
            m_trem = m_tnext - ovr;
        } else if (m_tnext) {   // Too large, use minimum
            m_trem = 1;
        } else {                // Stop after one-time event
            m_trem = 0;
        }
    }
}

poll::TimerAdapter::TimerAdapter(poll::OnDemand* target)
    : m_target(target)
{
    // Parent should call timer_once(), timer_every(), etc.
}

void poll::TimerAdapter::timer_event()
{
    m_target->request_poll();
}

satcat5::irq::VirtualTimer::VirtualTimer(
        poll::OnDemand* obj, GenericTimer* timer, unsigned usec)
    : m_target(obj)
    , m_timer(timer)
    , m_interval(usec)
    , m_tref(timer->now())
{
    // Nothing else to do at this time.
}

void satcat5::irq::VirtualTimer::poll_always()
{
    if (m_timer->elapsed_test(m_tref, m_interval))
        m_target->request_poll();
}
