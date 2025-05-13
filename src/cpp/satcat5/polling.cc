//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/interrupts.h> // For AtomicLock
#include <satcat5/list.h>
#include <satcat5/polling.h>

namespace poll = satcat5::poll;
using satcat5::irq::AtomicLock;
using satcat5::util::TimeRef;
using satcat5::util::ListCore;

// Enable runtime checks for severe infrastructure errors?
// This aids debugging but has severe performance penalties.
// Setting this flag is not recommended for production designs.
#ifndef SATCAT5_PARANOIA
#define SATCAT5_PARANOIA 0
#endif

#if SATCAT5_PARANOIA
    #include <satcat5/log.h>
    static unsigned panic(const char* label) {
        static constexpr unsigned* NULLPTR = 0;
        satcat5::log::Log(satcat5::log::CRITICAL, label);
        return *NULLPTR; // Intentionally segfault.
    }
#else
    static unsigned panic(const char* label) {return 0;} // GCOVR_EXCL_LINE
#endif

// Global linked list for each major polling type:
// (Use of global pointer ensures this is initialized before any
//  individual object constructor, including other globals.)
static poll::Always*    g_list_always = 0;
static poll::OnDemand*  g_list_demand = 0;
static poll::Timer*     g_list_timer  = 0;

// Placeholder used if no other timer is available.
satcat5::util::NullTimer null_timer;

// Global pointer to the preferred timer object.
// (As above, syntax ensures expected initialization order.)
static TimeRef* g_main_timer = &null_timer;

// Global helper object for Timers.
poll::Timekeeper poll::timekeeper;

// Human-readable label for AtomicLock.
static const char* const LBL_POLL = "POLL";

//! Global helper object that services all `OnDemand` objects.
//!
//! There is a single global instance of the `OnDemandHelper` class.
//! It is the object that issues callbacks to all `OnDemand` objects
//! that have requested attention.
//!
//! This class inherits from `Always`, meaning that it is polled every
//! time the user calls `service` or `service_all`, which causes it to
//! check the global queue of OnDemand requests.
class poll::OnDemandHelper final : public poll::Always {
public:
    // Constructor is the only public method.
    OnDemandHelper() : m_item(0) {}

    // Are we holding on to a working sublist?
    inline unsigned count() const
        {return ListCore::len(m_item);}

    // Forcibly discard all pending OnDemand objects and make sure
    // this object is the only one in "g_list_always".
    bool pre_test_reset() {
        bool ok = true;
        if (g_list_always != this)  {g_list_always = this;  ok = false;}
        if (m_item)                 {m_item = 0;            ok = false;}
        if (m_next)                 {m_next = 0;            ok = false;}
        return ok;
    }

    // Remove an item from the global list or the working sublist.
    // (Safe to call "remove" on both lists, no-op if there's no match.)
    void remove(poll::OnDemand* ptr) {
        AtomicLock lock(LBL_POLL);
        ListCore::remove(g_list_demand, ptr);
        if (m_item) ListCore::remove(m_item, ptr);
    }

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
        if (SATCAT5_PARANOIA && ListCore::has_loop(m_item)) {
            panic("poll_demand"); return;
        }
        while (m_item) {
            poll::OnDemand* next = list_pop();
            next->poll_demand();
        }
    }
} on_demand_helper;

// Forcibly reset on_demand_helper and unregister all other global event handlers.
bool poll::pre_test_reset() {
    bool ok = true;
    if (!on_demand_helper.pre_test_reset()) ok = false;
    if (!timekeeper.pre_test_reset())       ok = false;
    if (g_list_demand)  {g_list_demand = 0; ok = false;}
    if (g_list_timer)   {g_list_timer = 0;  ok = false;}
    return ok;
}

void poll::service() {
    // Optional sanity check before we start.
    if (SATCAT5_PARANOIA && ListCore::has_loop(g_list_always)) {
        panic("poll_always"); return;
    }
    // Poll each block on the global list exactly once.
    // (This includes the on_demand_helper defined above.)
    poll::Always* item = g_list_always;
    while (item) {
        item->poll_always();
        item = item->m_next;
    }
}

void poll::service_all(unsigned limit) {
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
poll::Always::~Always() {
    // Remove ourselves from the global linked list.
    AtomicLock lock(LBL_POLL);
    ListCore::remove(g_list_always, this);
}
#endif

unsigned poll::Always::count_always() {
    AtomicLock lock(LBL_POLL);
    return ListCore::len(g_list_always);
}

#if SATCAT5_ALLOW_DELETION
poll::OnDemand::~OnDemand() {
    AtomicLock lock(LBL_POLL);

    // If we're idle, there's nothing else to do.
    if (m_idle) return;

    // Otherwise, remove ourselves from the pending queue.
    // (This may be either g_list_demand or on_demand_helper.)
    on_demand_helper.remove(this);
}
#endif

void poll::OnDemand::request_poll() {
    // After safety-check, add this item to the head of the list.
    // (Re-adding an item creates an infinite loop in the linked-list.)
    AtomicLock lock(LBL_POLL);
    if (m_idle) {
        m_idle = 0;
        if (SATCAT5_PARANOIA && ListCore::contains(g_list_demand, this)) {
            panic("poll_request");
        } else {
            ListCore::add(g_list_demand, this);
        }
    }
}

void poll::OnDemand::request_cancel() {
    // If applicable, remove ourselves from the pending-item list.
    AtomicLock lock(LBL_POLL);
    if (!m_idle) {
        m_idle = 1;
        on_demand_helper.remove(this);
    }
}

unsigned poll::OnDemand::count_ondemand() {
    AtomicLock lock(LBL_POLL);
    return ListCore::len(g_list_demand);
}

poll::Timekeeper::Timekeeper()
    : m_tref(g_main_timer->now())
{
    // No other initialization required.
}

bool poll::Timekeeper::clock_ready() const {
    return g_main_timer != &null_timer;
}

satcat5::util::TimeRef* poll::Timekeeper::get_clock() const {
    return g_main_timer;
}

void poll::Timekeeper::set_clock(TimeRef* timer) {
    // Atomically set the global clock pointer.
    AtomicLock lock(LBL_POLL);
    g_main_timer = timer ? timer : &null_timer;
    m_tref = g_main_timer->now();
}

void poll::Timekeeper::suggest_clock(TimeRef* timer) {
    // Keep the clock with better resolution
    AtomicLock lock(LBL_POLL);
    if (timer && timer->ticks_per_msec() > g_main_timer->ticks_per_msec())
        set_clock(timer);
}

bool poll::Timekeeper::pre_test_reset() {
    // Since timekeeper is global, explicitly purge persistent state.
    request_cancel();       // Cancel any pending callbacks.
    set_clock(0);           // Reset the reference clock.
    return true;            // All initial states are valid.
}

void poll::Timekeeper::poll_demand() {
    // Measure elapsed time if a reference clock is available.
    unsigned elapsed_msec = 1;      // Default = 1 msec
    if (clock_ready()) {
        // Measure elapsed time since last call to "elapsed_msec".
        // ("m_tref" updated to g_main_timer->now(), less fractional leftovers.)
        AtomicLock lock(LBL_POLL);
        elapsed_msec = m_tref.increment_msec();
        if (!elapsed_msec) return;  // Less than 1 msec elapsed?
    }
    // Optional sanity check before we start.
    if (SATCAT5_PARANOIA && ListCore::has_loop(g_list_timer)) {
        panic("poll_timer"); return;
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
poll::Timer::~Timer() {
    // Remove ourselves from the global linked list.
    AtomicLock lock(LBL_POLL);
    ListCore::remove(g_list_timer, this);
}
#endif

unsigned poll::Timer::count_timer() {
    AtomicLock lock(LBL_POLL);
    return ListCore::len(g_list_timer);
}

void poll::Timer::timer_once(unsigned msec) {
    m_trem  = msec;
    m_tnext = 0;
}

void poll::Timer::timer_every(unsigned msec) {
    m_trem  = msec;
    m_tnext = msec;
}

void poll::Timer::timer_stop() {
    m_trem  = 0;
    m_tnext = 0;
}

void poll::Timer::query(unsigned elapsed_msec) {
    if (m_trem > elapsed_msec) {
        // Continue countdown...
        m_trem -= elapsed_msec;
    } else if (m_trem) {
        // Repeating timers adjust next interval to minimize cumulative drift.
        // (Do this first, since timer_event() may change the configuration.)
        unsigned ovr = elapsed_msec - m_trem;
        if (m_tnext > ovr) {
            // Overshoot is small enough to compensate accurately.
            // e.g., If timer scheduled every 1000 msec fires 5 msec late,
            // then next interval should be 995 msec to get back on schedule.
            m_trem = m_tnext - ovr;
        } else if (m_tnext) {
            // Overshoot is too large to fix, minimum delay is 1 msec.
            m_trem = 1;
        } else {
            // Stop after one-time event
            m_trem = 0;
        }

        // Process the timer event notification.
        // (Any configuration changes overwrite the calculations above.)
        timer_event();
    }
}

poll::TimerAdapter::TimerAdapter(poll::OnDemand* target)
    : m_target(target)
{
    // Parent should call timer_once(), timer_every(), etc.
}

void poll::TimerAdapter::timer_event() {
    m_target->request_poll();
}

satcat5::irq::VirtualTimer::VirtualTimer(poll::OnDemand* obj, unsigned usec)
    : m_target(obj)
    , m_interval(usec)
    , m_tref(SATCAT5_CLOCK->now())
{
    // Nothing else to initialize.
}

void satcat5::irq::VirtualTimer::poll_always() {
    if (m_tref.interval_usec(m_interval))
        m_target->request_poll();
}

