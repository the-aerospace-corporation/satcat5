//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Define the API for generating ptp::Measurement events

#pragma once

#include <satcat5/list.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace ptp {
        //! A source for ptp::Measurement events, usually a ptp::Client.
        //! To use this class, derive a child class and call `notify_callbacks`
        //! for each completed ptp::Measurement handshake.  That method will
        //! call `ptp_ready` for each registered Callback object.
        class Source {
        public:
            inline void add_callback(satcat5::ptp::Callback* callback)
                { m_callbacks.add(callback); }

            inline void remove_callback(satcat5::ptp::Callback* callback)
                { m_callbacks.remove(callback); }

        protected:
            //! Notify all Callback objects of a new Measurement.
            void notify_callbacks(const satcat5::ptp::Measurement& meas);

            //! Linked list of registered callback objects.
            satcat5::util::List<satcat5::ptp::Callback> m_callbacks;
        };

        //! PTP callback accepts each complete measurement from the Source.
        //! To use this API, derive a child class that defines ptp_ready(...)
        //! and then call ptp::Source::add_callback(...).
        class Callback {
        public:
            // Callback method for incoming ptp::Measurement data.
            //! The child class MUST override this method.
            virtual void ptp_ready(const satcat5::ptp::Measurement& data) = 0;
        protected:
            //! If a source pointer is provided, call `add_callback`.
            explicit Callback(satcat5::ptp::Source* source);
            ~Callback();
            satcat5::ptp::Source* const m_source;
        private:
            friend satcat5::util::ListCore;
            satcat5::ptp::Callback* m_next;
        };
    }
}
