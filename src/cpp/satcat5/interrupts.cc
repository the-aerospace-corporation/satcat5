//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_timer.h>
#include <satcat5/interrupts.h>
#include <satcat5/list.h>
#include <satcat5/polling.h>
#include <satcat5/utils.h>

namespace irq   = satcat5::irq;
namespace util  = satcat5::util;

// Placeholder used if no timer is available.
class NullTimer : public satcat5::util::GenericTimer
{
public:
    NullTimer() : GenericTimer(1) {}
    u32 now() override {return 0;}
} null_timer;

// Global trackers for max time spent in interrupt or lock mode,
// plus the estimated depth of the stack pointer.
#if SATCAT5_IRQ_STATS
    util::RunningMax irq::worst_irq;
    util::RunningMax irq::worst_lock;
    util::RunningMax irq::worst_stack;
    static u8* stack_ref = 0;
#endif

// Context indicators increment g_lock_count by a huge amount.
static const u32 USER_CONTEXT       = 0x40000000u;
static const u32 INTERRUPT_CONTEXT  = 0x80000000u;

// Global variable indicates the current interrupt & lock nesting level.
// This is necessary because atomic_xx methods may be called even
//  before the global irq_ctrl has been initialized, since the order
//  of operations for global constructors is ill-defined across files,
//  and atomic_xx is a side-effect of many other constructors.
static u32 g_lock_count = 0;

// Global linked list of all interrupt handlers.
// (See note above. This is always initialized before any C++ constructor.)
static irq::Handler* g_irq_list = 0;

// Global timer object for interrupt and lock statistics.
static util::GenericTimer* g_timer = 0;

// Global pointer to the active Controller object.
static irq::Controller* g_irq_ctrl = 0;

#if SATCAT5_ALLOW_DELETION
irq::Controller::~Controller()
{
    // Clear all global state.
    g_lock_count = 0;
    g_irq_ctrl = 0;
    g_irq_list = 0;
    g_timer = 0;
}
#endif

void irq::Controller::stop()
{
    irq::AtomicLock lock("IRQ_HANDLER");

    // Sanity check so we don't do this twice...
    if (g_lock_count < USER_CONTEXT) return;

    // Unregister every object on the global list.
    irq::Handler* ptr = g_irq_list;
    while (g_irq_ctrl && ptr) {
        if (ptr->m_irq_idx >= 0) irq_unregister(ptr);
        ptr = ptr->m_next;
    }
    g_irq_list = 0;

    // Return to the pre-init context.
    g_lock_count -= USER_CONTEXT;
}

void irq::Controller::init(util::GenericTimer* timer)
{
    // Register each of the interrupt handlers.
    irq::Handler* irq = g_irq_list;
    while (irq) {
        irq_register(irq);
        irq = util::ListCore::next(irq);
    }

    // Linking timer now resolves a chicken-and-egg problem if timer
    // depends on a ConfigBus that needs this InterruptController.
    // Note the current stack frame as an estimate of the minimum depth.
#if SATCAT5_IRQ_STATS
    g_timer = timer ? timer : &null_timer;
    stack_ref = (u8*)__builtin_frame_address(0);
#endif

    // Update internal state as we enter regular runtime.
    g_irq_ctrl = this;
    g_lock_count = USER_CONTEXT;
}

bool irq::Controller::is_initialized()
{
    return (g_lock_count >= USER_CONTEXT);
}
bool irq::Controller::is_irq_context()
{
    return (g_lock_count >= INTERRUPT_CONTEXT);
}

bool irq::Controller::is_irq_or_locked()
{
    return (g_lock_count > USER_CONTEXT);
}

void irq::Controller::irq_acknowledge(irq::Handler* obj)
{
    // Default handler does nothing.
}

// Note: This method must be static for compatibility with the usual
//       callback signature of most legacy-C interrupt handlers.
void irq::Controller::interrupt_static(irq::Handler* obj)
{
    u32 tstart, elapsed = 0;

    // While in interrupt mode, increment nested-lock count to
    // prevent duplicate calls to hal_irq_pause().
    g_lock_count += INTERRUPT_CONTEXT;

    // In rapid sequence:
    //  * Note start time (if enabled)
    //  * Call the event handler
    //  * Acknowledge interrupt
    //  * Note elapsed time
    if (SATCAT5_IRQ_STATS) tstart = g_timer->now();
    obj->irq_event();
    g_irq_ctrl->irq_acknowledge(obj);
    if (SATCAT5_IRQ_STATS) elapsed = g_timer->elapsed_ticks(tstart);

#if SATCAT5_IRQ_STATS
    // If enabled, update per-interrupt and global time statistics.
    worst_irq.update(obj->m_label, elapsed);
    if (elapsed > obj->m_max_irqtime)
        obj->m_max_irqtime = elapsed;

    // Also update the estimated maximum stack-depth.
    // Note: This assumes stack grows "downward" per common convention.
    //       If this is wrong, the estimate is useless but does no harm.
    unsigned stack_now = (unsigned)(stack_ref - (u8*)__builtin_frame_address(0));
    worst_stack.update("STACK", stack_now);
#endif

    // Restore original lock-count.
    g_lock_count -= INTERRUPT_CONTEXT;
}

irq::ControllerNull::ControllerNull(util::GenericTimer* timer)
{
    init(timer);
}

void irq::ControllerNull::service_all()
{
    irq::Handler* irq = g_irq_list;
    while (irq) {
        service_one(irq);
        irq = util::ListCore::next(irq);
    }
}

irq::Handler::Handler(const char* lbl, int irq)
    : m_label(lbl)
    , m_irq_idx(irq)
    , m_max_irqtime(0)
    , m_next(0)
{
    irq::AtomicLock lock("IRQ_HANDLER");

    if (m_irq_idx >= 0) {
        // Add this interrupt handler to the global list.
        util::ListCore::add(g_irq_list, this);

        // Register now if init() has already been called.
        // (Otherwise, registration is handled by that method.)
        if (g_lock_count >= USER_CONTEXT)
            g_irq_ctrl->irq_register(this);
    }
}

#if SATCAT5_ALLOW_DELETION
irq::Handler::~Handler()
{
    irq::AtomicLock lock("IRQ_HANDLER");

    // Ignore placeholder interrupts (see above)
    if (m_irq_idx < 0) return;

    // If init() has been called, unregister this interrupt.
    if (g_lock_count >= USER_CONTEXT)
        g_irq_ctrl->irq_unregister(this);

    // Remove ourselves from the global linked list.
    util::ListCore::remove(g_irq_list, this);
}
#endif

irq::Adapter::Adapter(const char* lbl, int irq, satcat5::poll::OnDemand* obj)
    : irq::Handler(lbl, irq)
    , m_obj(obj)
{
    // No other initialization required.
}

#if SATCAT5_ALLOW_DELETION
irq::Adapter::~Adapter()
{
    // Parent has already performed all required cleanup.
}
#endif

void irq::Adapter::irq_event()
{
    m_obj->request_poll();
}

irq::Shared::Shared(const char* lbl, int irq)
    : irq::Handler(lbl, irq)
{
    // No other initialization required.
}

#if SATCAT5_ALLOW_DELETION
irq::Shared::~Shared()
{
    // Parent has already performed all required cleanup.
}
#endif

void irq::Shared::irq_event()
{
    // Traverse the list, notifying each callback.
    irq::Handler* item = m_list.head();
    while (item) {
        item->irq_event();
        item = item->m_next;
    }
}

irq::AtomicLock::AtomicLock(const char* lbl)
    : m_lbl(lbl)
    , m_tstart(0)
    , m_held(1)
{
    // Disable interrupts EXACTLY ONCE regardless of nesting.
    if (g_lock_count++ == USER_CONTEXT) {
        g_irq_ctrl->irq_pause();
    }

    // Optionally start the stopwatch for this atomic operation.
    if (SATCAT5_IRQ_STATS && g_timer)
        m_tstart = g_timer->now();
}

irq::AtomicLock::~AtomicLock() {
    release();
}

void irq::AtomicLock::release() {
    if (m_held) {
        // Clear flag and update global statistics.
        m_held = 0;
#if SATCAT5_IRQ_STATS
        if (g_timer) {
            u32 elapsed = g_timer->elapsed_ticks(m_tstart);
            irq::worst_lock.update(m_lbl, elapsed);          // Update stats
        }
#endif
        // Enable interrupts EXACTLY ONCE regardless of nesting.
        if (--g_lock_count == USER_CONTEXT) {
            g_irq_ctrl->irq_resume();
        }
    }
}
