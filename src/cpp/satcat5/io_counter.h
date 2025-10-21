//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Inline byte and packet counters for statistics and diagnostics.
//!
//! \details
//! As a useful high-level diagnostic, many network interfaces report
//! bytes received, bytes sent, frames received, and frames sent over
//! any given interval.  The classes in this file make it easy to add
//! that capability to various SatCat5 interfaces.
//!

#pragma once

#include <satcat5/io_writeable.h>

namespace satcat5 {
    namespace io {
        //! Define a generic API for reporting traffic statistics.
        //! These functions report cumulative counters since the last reset.
        //! Each method includes a "reset" parameter, defaulting to true,
        //! to provide an atomic query+reset as the default operation.
        //! (i.e., Reporting accurate counter values since the last query.)
        class Counter {
        public:
            //! Bytes transferred since the last query.
            virtual unsigned byte_count(bool reset = true) = 0;

            //! Frames transferred since the last query.
            virtual unsigned frame_count(bool reset = true) = 0;

            //! (Optional) Error events since the last query.
            virtual unsigned error_count(bool reset = true) // GCOVR_EXCL_LINE
                { return 0; }                               // GCOVR_EXCL_LINE
        };

        //! Simple implementation of the Counter API.
        //!
        //! This class can be used as a standalone unit, by calling the
        //! public API for `byte_incr`, `frame_incr`, and `error_incr`.
        //!
        //! Alternately, a child class may directly increment member
        //! variables `m_byte_ct`, `m_frm_ct`, and `m_err_ct`.
        //! For an example based on WriteableRedirect, \see CounterInline.
        class CounterSimple : public satcat5::io::Counter {
        public:
            // Implement the Counter API.
            unsigned byte_count(bool reset = true) override;
            unsigned frame_count(bool reset = true) override;
            unsigned error_count(bool reset = true) override;

            //! Increment any of the internal counters.
            inline void byte_incr(unsigned incr)
                { m_byte_ct += incr; }
            inline void frame_incr(unsigned incr)
                { m_frm_ct += incr; }
            inline void error_incr(unsigned incr)
                { m_err_ct += incr; }

        protected:
            //! Constructor is only accessible to the child object.
            constexpr CounterSimple()
                : m_byte_ct(0), m_err_ct(0), m_frm_ct(0), m_frm_len(0) {}
            ~CounterSimple() {}

            // Counter variables are incremented by the child class.
            unsigned m_byte_ct;     //!< Cumulative byte count
            unsigned m_err_ct;      //!< Cumulative error count
            unsigned m_frm_ct;      //!< Cumulative frame count
            unsigned m_frm_len;     //!< Length of current frame
        };

        //! Overlay class for adding counters to any Writeable interface.
        class CounterInline
            : public satcat5::io::CounterSimple
            , public satcat5::io::WriteableRedirect
        {
        public:
            //! Link this object to its ultimate destination.
            explicit constexpr CounterInline(satcat5::io::Writeable* dst)
                : WriteableRedirect(dst) {}

            // Implement the Writeable API.
            void write_abort() override;
            void write_bytes(unsigned nbytes, const void* src) override;
            bool write_finalize() override;
        protected:
            void write_next(u8 data) override;
        };

        //! Data structure for combined transmit and receive statistics.
        struct TrafficStats {
            unsigned sent_bytes;    //!< Bytes sent to remote device
            unsigned sent_frames;   //!< Frames sent to remote device
            unsigned rcvd_bytes;    //!< Bytes received from remote device
            unsigned rcvd_frames;   //!< Valid frames received from device
            unsigned rcvd_errors;   //!< Invalid frames received from device

            TrafficStats() = default;
            TrafficStats(const TrafficStats& t) = default;
            TrafficStats& operator=(const TrafficStats& t) = default;

            //! Nonzero activity on any of the counters?
            bool any() const;

            //! Read updated statistics from a transmit/receive pair.
            //! This query resets counters in the Tx and Rx objects.
            static TrafficStats query(
                satcat5::io::Counter& rx,
                satcat5::io::Counter& tx);
        };
    }
}
