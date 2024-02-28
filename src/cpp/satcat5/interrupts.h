//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Platform-agnostic classes for interrupt management.
//
// Also includes primitives for uninterruptible atomic operations. (In most
// baremetal embedded systems this simply means disabling interrupts.)
//
// Each of the included primitives includes built-in tools for measuring
// elapsed time.  Interrupt service routines and uninterruptible sections
// should always be VERY quick, so we track the worst offenders.
//

#pragma once

#include <satcat5/list.h>
#include <satcat5/types.h>

// By default, time statistics are enabled.
#ifndef SATCAT5_IRQ_STATS
#define SATCAT5_IRQ_STATS   1
#endif

namespace satcat5 {
    namespace irq {
        // Nestable "lock" object that enters critical section on creation,
        // and returns to normal operation when it falls out of scope.
        class AtomicLock final {
        public:
            explicit AtomicLock(const char* lbl);
            ~AtomicLock();

            void release();

        private:
            const char* const m_lbl;
            u32 m_tstart;
            bool m_held;
        };

        // Special index "-1" indicates a disabled or unconnected interrupt.
        constexpr int IRQ_NONE = -1;

        // Control object for registering interrupt handlers and handling
        // nested calls to atomic_start, atomic_end, etc.  Children should
        // implement the specified platform-specific methods.
        class Controller {
        public:
            // Register all InterruptHandler objects (see below).
            // The timer argument is optional but allows collection of
            // statistics about time spent in each interrupt handler.
            // User MUST call this function after exactly once, after
            // creation of all InterruptHandlers and before enabling
            // platform-specific interrupt infrastructure.
            void init(satcat5::util::GenericTimer* timer = 0);

            // Are we currently in an interrupt or lock context?
            static bool is_initialized();
            static bool is_irq_context();
            static bool is_irq_or_locked();

            // Unregister ALL interrupt handlers.
            // (For safety, this must be called before the destructor, since
            //  cleanup requires the use of various virtual methods.)
            void stop();

        protected:
            friend satcat5::irq::AtomicLock;
            friend satcat5::irq::Handler;

            // Only children should create or destroy base class.
            Controller() {}
            ~Controller() SATCAT5_OPTIONAL_DTOR;

            // Static interrupt service routine.
            // Child MUST call this method whenever an interrupt occurs.
            static void interrupt_static(satcat5::irq::Handler* obj);

            // Prevent preemption from "pause" until "resume".
            // May be implemented by mutex, disabling interrupts, etc.
            // Child MUST override these two methods.
            virtual void irq_pause() = 0;
            virtual void irq_resume() = 0;

            // Register the callback for an interrupt-handler.
            // Child MUST override this method.
            virtual void irq_register(satcat5::irq::Handler* obj) = 0;

            // Un-register the callback for an interrupt handler.
            // Child MUST override this method.
            virtual void irq_unregister(satcat5::irq::Handler* obj) = 0;

            // Post-handler acknowledgement, notification, and cleanup.
            // Child SHOULD override this method if such action is required.
            virtual void irq_acknowledge(satcat5::irq::Handler* obj);
        };

        // A do-nothing placeholder implementation of irq::Controller .
        // Instantiate this class if interrupts are handled outside of SatCat5
        // infrastructure and no other hardware abstraction is available.
        class ControllerNull final
            : public satcat5::irq::Controller {
        public:
            // Constructor accepts an optional Timer pointer, if available.
            explicit ControllerNull(satcat5::util::GenericTimer* timer = 0);
            ~ControllerNull() {}

            // User should call one of the "service" methods whenever a
            // SatCat5-related interrupt occurs.
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

        // Parent class for any object that responds to CPU interrupts.
        // Child class MUST:
        //   * Call the Handler constructor.
        //   * Override irq_event()
        //   * Ensure that irq_event() always returns promptly (<< 100 usec).
        class Handler {
        public:
            // Human-readable label, for debugging.
            const char* const m_label;

            // IRQ index for this interrupt handler.
            const int m_irq_idx;

        protected:
            friend satcat5::irq::Controller;

            // Only children should create or destroy base class.
            Handler(const char* lbl, int irq);
            ~Handler() SATCAT5_OPTIONAL_DTOR;

            // Method called whenever an interrupt is triggered.
            virtual void irq_event() = 0;

            // Statistics tracking for time consumed by this interrupt.
            u32 m_max_irqtime;

        private:
            // Linked list of all Handler objects.
            friend satcat5::irq::Shared;
            friend satcat5::util::ListCore;
            satcat5::irq::Handler* m_next;
        };

        // Adapter connects a hardware interrupt to any OnDemand object.
        class Adapter : public satcat5::irq::Handler {
        public:
            Adapter(const char* lbl, int irq, satcat5::poll::OnDemand* obj);
            ~Adapter() SATCAT5_OPTIONAL_DTOR;

        protected:
            void irq_event() override;
            satcat5::poll::OnDemand* const m_obj;
        };

        // Shared interrupt handler calls all children for any parent event.
        // (Children should all be registered with index = IRQ_NONE.)
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

        // Global tracking of the worst offenders for excessive
        // time spent in atomic-lock or interrupt-handler mode,
        // as well as the maximum stack depth.
        #if SATCAT5_IRQ_STATS
            extern satcat5::util::RunningMax
                worst_irq, worst_lock, worst_stack;
        #endif
    }
}
