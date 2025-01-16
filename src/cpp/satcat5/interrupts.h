//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Platform-agnostic API for interrupt management.
//!
//! \details
//! This file defines a platform-agnostic interface for designating
//! interrrupt handlers and responding to those interrupts.
//!
//! By default, this system does nothing.  However, when linked to a
//! platform-specific interrupt controller, such as the ones defined in
//! hal_samv71/interrupts.h or hal_ublaze/interrupts.h, then each
//! irq::Handler object will be registered as an interrupt handler,
//! calling irq_event() whenever a hardware interrupt is received.
//!
//! This file also defines primitives for uninterruptible atomic operations.
//! For now, the SatCat5 main-loop (see polling.h) is a single-threaded
//! event loop that allows cooperative multitasking using an event queue.
//! Except for hardware interrupts, event handling is sequential.  The
//! `AtomicLock` mutex defined here simply disables hardware interrupts
//! to create uninterruptible critical sections.  The `AtomicLock` mutex
//! is reentrant (i.e., it is safe to lock twice, then unlock twice).
//!
//! Each of the included primitives includes built-in tools for measuring
//! elapsed time.  Interrupt service routines and uninterruptible sections
//! should always be VERY quick, so we track the worst offenders.

#pragma once

#include <satcat5/list.h>
#include <satcat5/timeref.h>
#include <satcat5/types.h>

// By default, time statistics are enabled.
#ifndef SATCAT5_IRQ_STATS
#define SATCAT5_IRQ_STATS   1
#endif

namespace satcat5 {
    namespace irq {
        //! Automatic lock or mutex
        //!
        //! \link interrupts.h SatCat5 interrupt-API concepts. \endlink
        //!
        //! This nestable mutex object enters a lock/critical-section on
        //! creation, and releases the lock when it falls out of scope.
        class AtomicLock final {
        public:
            //! Creating this object starts a critical section.
            explicit AtomicLock(const char* lbl);
            ~AtomicLock();

            //! Optionally release this lock before the destructor is called.
            void release();

        private:
            const char* const m_lbl;
            satcat5::util::TimeVal m_tstart;
            bool m_held;
        };

        //! Special index "-1" indicates a disabled or unconnected interrupt.
        constexpr int IRQ_NONE = -1;

        //! Platform-agnostic interrupt controller
        //!
        //! \link interrupts.h SatCat5 interrupt-API concepts. \endlink
        //!
        //! This is the parent class for platform-specific interrupt systems.
        //! This control object registers interrupt handlers and handles
        //! nested calls to atomic_start, atomic_end, etc.  Children must
        //! implement the specified platform-specific methods.
        class Controller {
        public:
            //! Start the interrupt controller.
            //! Link all registered irq::Handler objects (see below).
            //! The timer argument is optional but allows collection of
            //! statistics about time spent in each interrupt handler.
            //! If none is provided, statistics use SATCAT5_CLOCK.
            //! The platform-specific implementation MUST call this function
            //! exactly once, when it is ready to begin servicing interrupts.
            void init(satcat5::util::TimeRef* timer = 0);

            //! Has init() been called?
            static bool is_initialized();
            //! Are we currently servicing an interrupt?
            static bool is_irq_context();
            //! Are we currently in a critical-section?
            static bool is_irq_or_locked();

            //! Unregister ALL interrupt handlers.
            //! (For safety, this must be called before the destructor, since
            //!  cleanup may require the use of various virtual methods.)
            void stop();

        protected:
            friend satcat5::irq::AtomicLock;
            friend satcat5::irq::Handler;

            //! Only children should create or destroy base class.
            Controller() {}
            ~Controller() SATCAT5_OPTIONAL_DTOR;

            //! Static interrupt service routine.
            //! Child MUST call this method whenever an interrupt occurs.
            static void interrupt_static(satcat5::irq::Handler* obj);

            //! Prevent preemption from "pause" until "resume".
            //! May be implemented by mutex, disabling interrupts, etc.
            //! Child MUST override these two methods.
            //!@{
            virtual void irq_pause() = 0;   //! Disable hardware interrupts.
            virtual void irq_resume() = 0;  //! Re-enable hardware interrupts.
            //!@}

            //! Register the callback for an interrupt-handler.
            //! Child MUST override this method.
            virtual void irq_register(satcat5::irq::Handler* obj) = 0;

            //! Un-register the callback for an interrupt handler.
            //! Child MUST override this method.
            virtual void irq_unregister(satcat5::irq::Handler* obj) = 0;

            //! Post-handler acknowledgement, notification, and cleanup.
            //! Child SHOULD override this method if such action is required.
            virtual void irq_acknowledge(satcat5::irq::Handler* obj);
        };

        //! A do-nothing placeholder implementation of irq::Controller .
        //!
        //! \link interrupts.h SatCat5 interrupt-API concepts. \endlink
        //!
        //! Instantiate this class if interrupts are handled outside of SatCat5
        //! infrastructure and no other hardware abstraction is available.
        class ControllerNull final
            : public satcat5::irq::Controller {
        public:
            //! Constructor accepts an optional Timer pointer, if available.
            explicit ControllerNull(satcat5::util::TimeRef* timer = 0);
            ~ControllerNull() {}

            //! User should call one of the "service" methods whenever a
            //! SatCat5-related interrupt occurs.
            void service_all();
            inline void service_one(satcat5::irq::Handler* obj)
                {satcat5::irq::Controller::interrupt_static(obj);}

        protected:
            // Empty hardware-abstraction overrides.
            void irq_pause() override {}
            void irq_resume() override {}
            void irq_register(satcat5::irq::Handler* obj) override {}
            void irq_unregister(satcat5::irq::Handler* obj) override {}
            void irq_acknowledge(satcat5::irq::Handler* obj) override {}
        };

        //! Parent object for receiving interrupt-handler callbacks.
        //!
        //! \link interrupts.h SatCat5 interrupt-API concepts. \endlink
        //!
        //! Parent class for any object that responds to a specific hardware
        //! interrupt.  Examples include cfg::ConfigBusMmap, which shares
        //! a single hardware interrupt amongst all ConfigBus peripherals.
        //!
        //! Child class MUST:
        //!   * Call the Handler constructor.
        //!   * Override irq_event()
        //!   * Ensure that irq_event() always returns promptly (<< 100 usec).
        //!
        //! Interrupt handlers must execute very quickly because they block
        //! other interrupt handlers from executing.  Handlers that can wait
        //! a few milliseconds to respond should consider deferring that work
        //! using an `OnDemand` event handler.  (i.e., By clearing the hardware
        //! interrupt and calling request_poll().)
        //!
        //! \see satcat5::irq::Adapter satcat5::poll::OnDemand
        class Handler {
        public:
            //! Human-readable label, for debugging.
            const char* const m_label;

            //! IRQ index for this interrupt handler.
            const int m_irq_idx;

        protected:
            friend satcat5::irq::Controller;

            //! Only children should create or destroy base class.
            Handler(const char* lbl, int irq);
            ~Handler() SATCAT5_OPTIONAL_DTOR;

            //! Method called whenever an interrupt is triggered.
            virtual void irq_event() = 0;

            //! Statistics tracking for time consumed by this interrupt.
            u32 m_max_irqtime;

        private:
            // Linked list of all Handler objects.
            friend satcat5::irq::Shared;
            friend satcat5::util::ListCore;
            satcat5::irq::Handler* m_next;
        };

        //! Adapter connects a hardware interrupt to any OnDemand object.
        //!
        //! \link interrupts.h SatCat5 interrupt-API concepts. \endlink
        //!
        //! This is often used with the poll::timekeeper object (polling.h),
        //! linking a hardware timer interrupt to the SatCat5 polling system.
        //! It can also be used to facilitate deferred interrupt handling.
        class Adapter : public satcat5::irq::Handler {
        public:
            Adapter(const char* lbl, int irq, satcat5::poll::OnDemand* obj);
            ~Adapter() SATCAT5_OPTIONAL_DTOR;

        protected:
            void irq_event() override;
            satcat5::poll::OnDemand* const m_obj;
        };

        //! Shared interrupt handler calls all children for any parent event.
        //! Use this if several irq::Handler objects share a hardware interrupt.
        //! (Children should all be registered with index = IRQ_NONE.)
        class Shared final : public satcat5::irq::Handler {
        public:
            Shared(const char* lbl, int irq);
            ~Shared() SATCAT5_OPTIONAL_DTOR;

            // Add a child to the list.
            inline void add(satcat5::irq::Handler* child)
                {m_list.add(child);}

        protected:
            void irq_event() override;

            satcat5::util::List<satcat5::irq::Handler> m_list;
        };

        //! Hard-reset of global variables at the start of each unit test.
        //! (Unit testing only, should not be called in production.)
        //!
        //! A hard reset may leak memory but prevents contamination of global
        //! state across tests, which can be extremely difficult to debug.
        //! Returns true if globals were already in the expected state.
        bool pre_test_reset();

        //! Statistics tracking for critical sections.
        //!
        //! \link interrupts.h SatCat5 interrupt-API concepts. \endlink
        //!
        //! For diagnostics purposes, these global objects track the worst
        //! offenders for excessive time spent in a critical section, slow
        //! interrupt handlers, and maximum observed stack depth.
        //!@{
        #if SATCAT5_IRQ_STATS
            extern satcat5::util::RunningMax
                worst_irq, worst_lock, worst_stack;
        #endif
        //!@}
    }
}
