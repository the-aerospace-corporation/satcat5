//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Inline checksum insertion (ChecksumTx) and verification (ChecksumRx).
//!
//! \details
//! Many frame formats consist of frame data followed by a checksum.
//! io::ChecksumTx and io::ChecksumRx define two templates for working with
//! such streams. The templates are able to work with any byte-aligned checksum
//! with byte-aligned inputs, including most CRC types and many other formats.
//!
//! Each template accepts data using the io::Writeable interface and writes
//! modified data to a designated io::Writeable pointer:
//!  * `ChecksumTx`: For each incoming frame, append the calculated checksum.
//!  * `ChecksumRx`: For each incoming frame, strip the last N bytes and
//!    compare against the calculated checksum. If it is a match call
//!    write_finalize(), and otherwise call write_abort().
//!
//! In all child classes of either template, the user MUST override the methods
//! write_next() and write_finalize() to calculate and format the checksum. For
//! child classes of io::ChecksumTx, the implementation of write_finalize()
//! MUST call chk_finalize(). For example usage, refer to eth::ChecksumTx and
//! eth::ChecksumRx.
//!
//! Template type `T` stores the checksum (u8/u16/u32/u64).
//! Template value `N` is the checksum length in bytes.
//!

#pragma once

#include <satcat5/io_writeable.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace io {
        //! Inline checksum insertion, appends FCS to each outgoing frame.
        //! \copydoc io_checksum.h
        template <class T, unsigned N> class ChecksumTx
            : public satcat5::io::Writeable
        {
        public:
            // Implement required API from Writeable:
            unsigned get_write_space() const override {
                // Reserve enough space to append FCS.
                unsigned nbytes = m_dst->get_write_space();
                return (m_ovr || nbytes < N) ? (0) : (nbytes - N);
            }

            void write_abort() override {
                m_chk = m_init;                     // Reset internal state
                m_ovr = false;
                m_dst->write_abort();               // Forward error event
            }

        protected:
            //! Only the child class has access to the constructor.
            ChecksumTx(satcat5::io::Writeable* dst, T init)
                : m_dst(dst), m_chk(init), m_init(init), m_ovr(false)
            {
                // Nothing else to initialize
            }

            void write_overflow() override {
                m_ovr = true;                       // Flag until end-of-frame.
            }

            //! Reset internal state and return true if the frame is valid.
            //! i.e., If false, do not forward the write_finalize() event.
            bool chk_finalize() {
                bool ovr = m_ovr;
                if (ovr) m_dst->write_abort();      // Forward error event?
                m_chk = m_init;                     // Reset internal state
                m_ovr = false;
                return !ovr;                        // Continue finalize event?
            }

            // Internal state:
            satcat5::io::Writeable* const m_dst;    //!< Output object
            T m_chk;                                //!< Checksum state
            const T m_init;                         //!< State after reset
            bool m_ovr;                             //!< Overflow flag
        };

        //! Check and remove FCS from each incoming frame.
        //! \copydoc io_checksum.h
        template <class T, unsigned N> class ChecksumRx
            : public satcat5::io::Writeable
        {
        public:
            //! Report cumulative error count since last reset.
            //! By default, each query resets the cumulative error counter.
            unsigned error_count(bool reset = true) {
                unsigned tmp = m_err_ct;
                if (reset) m_err_ct = 0;
                return tmp;
            }

            //! Increment the internal error counter.
            //! Some systems use the checksum error counter to consolidate
            //! tracking of multiple frame-error types. \see ccsds_aos.h.
            inline void error_incr()
                { ++m_err_ct; }

            //! Report cumulative packet count since last reset.
            //! By default, each query resets the cumulative error counter.
            unsigned frame_count(bool reset = true) {
                unsigned tmp = m_frm_ct;
                if (reset) m_frm_ct = 0;
                return tmp;
            }

            // Implement required API from Writeable:
            unsigned get_write_space() const override {
                return m_dst->get_write_space();
            }

            void write_abort() override {
                m_dst->write_abort();               // Forward error event
                m_chk = m_init;                     // Reset internal state
                m_bidx = 0;
                ++m_err_ct;                         // Count this as an error
            }

        protected:
            //! Only the child class has access to the constructor.
            ChecksumRx(satcat5::io::Writeable* dst, T init)
                : m_dst(dst), m_chk(init), m_init(init)
                , m_sreg(0), m_bidx(0), m_err_ct(0), m_frm_ct(0)
            {
                // Nothing else to initialize.
            }

            //! Child class MUST call sreg_match(...) during write_finalize().
            //! The child provides the FCS in a format that matches SREG.
            inline bool sreg_match(T fcs) {
                // Does the calculated FCS match the last N bytes in SREG?
                constexpr T MASK = satcat5::util::mask_lower<T>(8*N);
                bool ok = (m_bidx >= N) && ((fcs & MASK) == (m_sreg & MASK));
                // Reset internal state.
                m_chk = m_init;
                m_bidx = 0;
                // Call write_finalize() or write_abort().
                if (ok && m_dst->write_finalize()) {
                    ++m_frm_ct;
                    return true;
                } else {
                    ++m_err_ct;
                    if (!ok) m_dst->write_abort();
                    return false;
                }
            }

            //! Child class MUST call sreg_push(...) during write_next().
            //! If it returns true, update the checksum state appropriately.
            inline bool sreg_push(u8& data) {
                // FCS is in the last N bytes, but we can't predict end-of-frame.
                // Instead, buffer previous N bytes of input in a shift register.
                constexpr unsigned SHIFT = 8 * (N - 1);
                T tmp = static_cast<T>(data);       // Copy input...
                data = (u8)(m_sreg >> SHIFT);       // Pop oldest data
                m_sreg = (m_sreg << 8) | tmp;       // Push new data
                // Is the shift register currently full?
                if (m_bidx < N) {
                    ++m_bidx;                       // Wait until full...
                    return false;                   // No update to CRC
                } else {
                    m_dst->write_u8(data);          // Forward popped data
                    return true;                    // Request CRC update
                }
            }

            // Internal state:
            satcat5::io::Writeable* const m_dst;    //!< Output object
            T m_chk;                                //!< Checksum state
            const T m_init;                         //!< State after reset
            T m_sreg;                               //!< Big-endian input buffer
            unsigned m_bidx;                        //!< Bytes received
            unsigned m_err_ct;                      //!< Cumulative error count
            unsigned m_frm_ct;                      //!< Cumulative error count
        };
    }
}
