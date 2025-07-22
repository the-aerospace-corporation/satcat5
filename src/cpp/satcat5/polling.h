//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Core event-processing loop for SatCat5 software
//!
//! \details
//! This file defines the main event-processing loop for all SatCat5
//! software.  To function properly, SatCat5 requires users to connect
//! several subsystems to platform-specific logic:
//!  * Call timekeeper::request_poll() at regular intervals.
//!     * In FreeRTOS, this should be linked to the system tick.
//!       (See hal_freertos/satcat_task.h)
//!     * In Linux or Windows systems, use the PosixTimekeeper class.
//!       (See hal_posix/posix_utils.h)
//!     * In baremetal systems, this may be linked to a timer interrupt.
//!       (See cfgbus_timer.h for one possible implementation)
//!     * In other systems, consider using the VirtualTimer class.
//!  * Call satcat5::poll::service_all() at frequent intervals.
//!     * In FreeRTOS, this should be linked to the system tick.
//!     * In baremetal systems, this may be an infinite loop:
//!         `while(1) {satcat5::poll::service_all();}`
//!  * (Optional) Set the elapsed-time reference (TimeRef).
//!     * Use timekeeper::set_clock() to force a specific reference.
//!     * Use timekeeper::suggest_clock() to automatically select
//!       the "best" reference from among all suggested clocks.
//!     * If no TimeRef is provided, poll timekeeper at exactly 1 kHz.
//!
//! SatCat5 event-processing is single-threaded.  Each call to the main
//! service function (i.e., satcat5::poll::service_all()) processes all
//! queued events in sequence.
//!
//! There are three built-in event types:
//!  * satcat5::poll::Always
//!      This object is polled whenever the main service function is called.
//!      (Users may inherit from this class and override "poll_always".)
//!  * satcat5::poll::OnDemand
//!      This object is polled only after request_poll() method has been called.
//!      For example, many interrupt handlers call request_poll() in order to
//!      request additional service at the next convenient time.  This method
//!      is also used for io::Readable::data_rcvd() callbacks.
//!      (Users may inherit from this class and override "poll_demand".)
//!  * satcat5::poll::Timer
//!      Poll this object at a designated time, or at a designated interval.
//!      (Users may inherit from this class and override "timer_event".)


#pragma once

#include <satcat5/timeref.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace poll {
        // Prototype for internal helper objects.
        class OnDemandHelper;

        //! Single-pass service loop.
        //!
        //! \see satcat5::poll::service_all
        //!
        //! This function processes all queued events, then returns.
        //! Most users should instead call `service_all()`.
        void service();

        //! Multi-pass service loop
        //! Calling this function regularly is required for SatCat5 operation.
        //!
        //! \link polling.h SatCat5 event-loop concepts. \endlink
        //!
        //! This is the preferred service method, because it will continue
        //! processing queued events until the queue is empty or the iteration
        //! limit is reached.  Iterated polling is preferred because on-demand
        //! event processing often triggers additional event(s).  (For example,
        //! incoming data from a UART may pass data to a SLIP decoder, which
        //! may pass data to an IPv4 stack.)
        //!
        //! Users must call this method frequently.
        void service_all(unsigned limit = 100);

        //! Hard-reset of global variables at the start of each unit test.
        //! (Unit testing only, should not be called in production.)
        //!
        //! A hard reset may leak memory but prevents contamination of global
        //! state across tests, which can be extremely difficult to debug.
        //! Returns true if globals were already in the expected state.
        bool pre_test_reset();

        //! An "Always" object is polled whenever service() is called.
        //!
        //! \link polling.h SatCat5 event-loop concepts. \endlink
        //!
        //! Use this type sparingly, to avoid excessive CPU loading. To receive
        //! Always callbacks, derive a child class and override "poll_always()".
        class Always {
        public:
            //! Child class MUST override this method.
            //! (This method should rarely be called directly.)
            virtual void poll_always() = 0;

            //! Count active objects of this type.
            static unsigned count_always();

        protected:
            //! Registers this pollable object unless `auto_register = false`.
            //! (Only children should create or destroy the base class.)
            explicit Always(bool auto_register=true);
            ~Always() SATCAT5_OPTIONAL_DTOR;

            //! Register this pollable object, called by the constructor.
            void poll_register();

            //! Unregister this pollable object, called by the destructor.
            void poll_unregister();

        private:
            friend satcat5::poll::OnDemandHelper;
            friend satcat5::util::ListCore;
            friend void satcat5::poll::service();
            satcat5::poll::Always* m_next;  // Linked list to next object
        };

        //! An "OnDemand" object is polled only on request.
        //!
        //! \link polling.h SatCat5 event-loop concepts. \endlink
        //!
        //! A call to service() polls all pending OnDemand requests.
        //! This is the most common type of polling object.
        //! To receive OnDemand callbacks, derive a child class and override "poll_demand()".
        class OnDemand {
        public:
            //! Call this method to request polling at a later time.
            //! Safe to stack requests, but only one call to poll().
            void request_poll();

            //! Call this method to cancel a previous request_poll().
            void request_cancel();

            //! Count queued objects of this type (i.e., non-idle).
            static unsigned count_ondemand();

        protected:
            //! Deferred event handler, called after request().
            //! Child class MUST override this method.
            //! (Call "request_poll" to enqueue a callback to this method.)
            virtual void poll_demand() = 0;

            //! Register this pollable object.
            //! (Only children should create or destroy the base class.)
            constexpr OnDemand() : m_next(0), m_idle(1) {}
            ~OnDemand() SATCAT5_OPTIONAL_DTOR;

        private:
            friend satcat5::util::ListCore;
            friend satcat5::poll::OnDemandHelper;
            friend satcat5::ptp::Interface;
            satcat5::poll::OnDemand* m_next;    // Linked list to next object
            bool m_idle;                        // Item currently idle?
        };

        //! Global coordinator for multiple Timer objects.
        //! Polling this object regularly is required for SatCat5 operation.
        //!
        //! \link polling.h SatCat5 event-loop concepts. \endlink
        //!
        //! This class also stores the pointer to the system TimeRef.
        class Timekeeper : public satcat5::poll::OnDemand {
        public:
            Timekeeper();

            //! Get the system time reference, if one is set.
            //! Note: The SATCAT5_CLOCK macro is an alias for
            //!  satcat5::poll::timekeeper.get_clock().
            satcat5::util::TimeRef* get_clock() const;

            //! Has a system time reference been provided?
            bool clock_ready() const;

            //! Immediately set the system time reference.
            //! (Use this if you're sure which reference you want to use.)
            void set_clock(satcat5::util::TimeRef* timer);

            //! Compare the provided reference to the current TimeRef,
            //! and keep whichever is "better" by an internal heuristic.
            //! (Use this if there may be several possible references.)
            void suggest_clock(satcat5::util::TimeRef* timer);

            //! Reset timekeeper state at the start of each unit test.
            //! (Unit testing only, should not be called in production.)
            bool pre_test_reset();

        protected:
            void poll_demand() override;
            satcat5::util::TimeVal m_tref;
        };

        //! There is a single global instance of the Timekeeper class.
        //!
        //! \link polling.h SatCat5 event-loop concepts. \endlink
        //!
        //! User MUST link it to a once-per-millisecond event source
        //! such as a hardware interrupt or the VirtualTimer.
        extern Timekeeper timekeeper;

        //! Timer objects are polled after a fixed delay or at a regular interval.
        //!
        //! \link polling.h SatCat5 event-loop concepts. \endlink
        //!
        //! To poll a timer once after a fixed delay, call "timer_once()".
        //! To poll a timer at a regular interval, call "timer_every()".
        //! To receive timer callbacks, derive a child class and override "timer_event()".
        class Timer {
        public:
            //! Count all objects of this type, including idle timers.
            static unsigned count_timer();

            //! Configure a one-time notification after X milliseconds.
            void timer_once(unsigned msec);
            //! Configure a repeating notification every X milliseconds.
            void timer_every(unsigned msec);
            //! Stop all future notifications.
            void timer_stop();

            //! Accessor for recurring timer interval, if one is set.
            inline unsigned timer_interval() const {return m_tnext;}

            //! Accessor for time to next event, if one is set.
            inline unsigned timer_remaining() const {return m_trem;}

        protected:
            //! Register object in the idle state.
            //! (Only children should create or destroy the base class.)
            Timer();
            ~Timer() SATCAT5_OPTIONAL_DTOR;

            //! Child class MUST override this method.
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

        //! Connect a Timer to any OnDemand object.
        //!
        //! \link polling.h SatCat5 event-loop concepts. \endlink
        //!
        //! This object calls request_poll() whenever the timer_event() fires.
        class TimerAdapter : public satcat5::poll::Timer {
        public:
            explicit TimerAdapter(satcat5::poll::OnDemand* target);
        protected:
            void timer_event() override;
            satcat5::poll::OnDemand* const m_target;
        };
    }

    namespace irq {
        //! Poll any OnDemand object using a TimeRef.
        //!
        //! \link polling.h SatCat5 event-loop concepts. \endlink
        //!
        //! This class polls the system time (SATCAT5_CLOCK) and calls
        //! request_poll() at the designated interval.  On platforms that
        //! do not have easy access to hardware interrupts, this is the
        //! preferred method of polling the global timekeeper.
        class VirtualTimer : protected satcat5::poll::Always {
        public:
            //! Poll the designated object once every N microseconds.
            //! (As determined using the designated time reference.)
            VirtualTimer(
                satcat5::poll::OnDemand* obj, unsigned usec = 1000);

        protected:
            void poll_always() override;

            satcat5::poll::OnDemand* const m_target;
            unsigned const m_interval;
            satcat5::util::TimeVal m_tref;
        };
    }
}
