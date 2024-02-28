//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Systems for various types of polling
//
// Many SatCat5 tools require occasional calls to a "poll()" method.
// In the most basic form, the method is called at an irregular or
// occasional rate, often as one step in the program's main loop.
//
// This file provides various utilities for common types of polling, so
// that the end-user can call a single function, to service all SatCat5
// objects.  To use:
//  * Each object that requires polling inherits from the appropriate
//    parent class (see list below).
//  * Call satcat5::poll::timekeeper::request() exactly once per millisecond.
//    (For example, by linking the callback on a satcat5::cfg::Timer or
//     satcat5::polling::VirtualTimer to the global "timerkeeper" instance.)
//  * Call satcat5::poll::service() at frequent intervals.
//    (Usually as part of a main program loop; irregular timing OK.)
//
// The types provided here are:
//  * satcat5::poll::Always
//      Poll this object whenever the main polling function is called.
//  * satcat5::poll::OnDemand
//      Poll this object only if its request() method has been called
//      since the last call to poll().  (Often used in conjunction with
//      interrupts, to allow deferred action in the user context.)
//  * satcat5::poll::Timer
//      Poll this object every X milliseconds.
//

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace poll {
        // Prototype for internal helper objects.
        class OnDemandHelper;
        class Timekeeper;

        // The main function that handles all other polling.
        // End-user MUST call this function frequently.
        // (e.g., As part of their main program loop.)
        void service();

        // Repeatedly call service() until OnDemand requests are completed
        // or the iteration limit is reached, whichever comes first.
        // (Useful for unit-testing or if service() is only called rarely.)
        void service_all(unsigned limit = 100);

        // Poll this object whenever the main polling function is called.
        class Always {
        public:
            // Child class MUST override this method.
            // (This method should rarely be called directly.)
            virtual void poll_always() = 0;

            // Count active objects of this type.
            static unsigned count();

        protected:
            // Register this pollable object.
            // (Only children should create or destroy the base class.)
            Always();
            ~Always() SATCAT5_OPTIONAL_DTOR;

        private:
            friend satcat5::util::ListCore;
            friend void satcat5::poll::service();
            satcat5::poll::Always* m_next;  // Linked list to next object
        };

        // Poll this object only if its request() method has been called.
        class OnDemand {
        public:
            // Call this method to request polling at a later time.
            // Safe to stack requests, but only one call to poll().
            void request_poll();

            // Count queued objects of this type (i.e., non-idle).
            static unsigned count();

            // Deferred event handler, called after request().
            // Child class MUST override this method.
            // (This method should rarely be called directly.)
            virtual void poll_demand() = 0;

        protected:
            // Register this pollable object.
            // (Only children should create or destroy the base class.)
            OnDemand();
            ~OnDemand() SATCAT5_OPTIONAL_DTOR;

        private:
            friend satcat5::util::ListCore;
            friend satcat5::poll::OnDemandHelper;
            satcat5::poll::OnDemand* m_next;    // Linked list to next object
            bool m_idle;                        // Item currently idle?
        };

        // Coordinator for multiple "Timer" objects that receives
        // once-per-millisecond notifications (e.g., from cfg::Timer)
        class Timekeeper : public satcat5::poll::OnDemand {
        public:
            Timekeeper();

            // An optional GenericTimer reference should be used to improve
            // timer accuracy in cases where polling rate is less than 1 kHz.
            void set_clock(satcat5::util::GenericTimer* timer);

        protected:
            void poll_demand() override;
            satcat5::util::GenericTimer* m_clock;
            u32 m_tref;
        };

        // There is a single global instance of the Timekeeper class.
        // User MUST link it to a once-per-millisecond event source
        // such as a hardware interrupt or the VirtualTimer.
        extern Timekeeper timekeeper;

        // Poll this object every X milliseconds (set_timer_every) or as a
        // one-time event after a delay of X milliseconds (set_timer_once).
        class Timer {
        public:
            // Count all objects of this type, including idle timers.
            static unsigned count();

            // Setup recurring or one-time notifications.
            void timer_once(unsigned msec);
            void timer_every(unsigned msec);
            void timer_stop();

            // Accessor for recurring timer interval, if one is set.
            inline unsigned timer_interval() const {return m_tnext;}

        protected:
            // Register object in the idle state.
            // (Only children should create or destroy the base class.)
            Timer();
            ~Timer() SATCAT5_OPTIONAL_DTOR;

            // Child class MUST override this method.
            virtual void timer_event() = 0;

        private:
            // Event handler called by Timekeeper class.
            void query(unsigned elapsed_msec);

            friend satcat5::util::ListCore;
            friend satcat5::poll::Timekeeper;
            satcat5::poll::Timer* m_next;       // Linked list to next object
            unsigned m_trem;                    // Milliseconds to next event
            unsigned m_tnext;                   // Recurring timer interval
        };

        // Connect a Timer to any OnDemand object.
        class TimerAdapter : public satcat5::poll::Timer {
        public:
            explicit TimerAdapter(satcat5::poll::OnDemand* target);
        protected:
            void timer_event() override;
            satcat5::poll::OnDemand* const m_target;
        };
    }

    namespace irq {
        // Virtual timer-interrupt generator using any GenericTimer.
        class VirtualTimer : protected satcat5::poll::Always {
        public:
            // Poll the designated object once every N microseconds.
            // (As determined using the designated GenericTimer.)
            VirtualTimer(
                satcat5::poll::OnDemand* obj,
                satcat5::util::GenericTimer* timer,
                unsigned usec = 1000);

        protected:
            void poll_always() override;

            satcat5::poll::OnDemand* const m_target;
            satcat5::util::GenericTimer* const m_timer;
            unsigned const m_interval;
            u32 m_tref;
        };
    }
}
