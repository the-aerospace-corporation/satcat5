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
//! Because checksum validation is often tied to a network interface, these
//! classes include the io::Counter API for counting sent and received frames.
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

#include <satcat5/io_counter.h>
#include <satcat5/io_writeable.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace io {
        //! Parent class for non-template elements of ChecksumTx.
        //! This class is not used directly. \see ChecksumTx.
        class ChecksumTxCommon
            : public satcat5::io::CounterSimple
            , public satcat5::io::Writeable {
        public:
            // Implement the Writeable API:
            void write_abort() override;

        protected:
            //! Only the child class has access to the constructor.
            constexpr explicit ChecksumTxCommon(satcat5::io::Writeable* dst)
                : m_dst(dst), m_ovr(false) {}

            //! Reset internal state and return true if the frame is valid.
            //! i.e., If false, do not forward the write_finalize() event.
            bool chk_finalize();

            //! Reset the checksum calculation to its initial state.
            //! Child MUST implement this method, since data type is unknown.
            virtual void chk_reset() = 0;

            // Implement required API from Writeable:
            void write_overflow() override;

            // Internal state:
            satcat5::io::Writeable* const m_dst;    //!< Output object
            bool m_ovr;                             //!< Overflow flag
        };

        //! Inline checksum insertion, appends FCS to each outgoing frame.
        //! \copydoc io_checksum.h
        //!
        //! Child class is responsible for the following:
        //! * Implement the `chk_reset()` method.
        //! * Implement the `write_next()` method.  This method must
        //!   update the checksum calculation and increment `m_frm_len`.
        //! * Implement the `write_finalize()` method.  This method must
        //!   write the calculated checksum, then call `chk_finalize()`,
        //!   then proceed only if the returned value is true.
        template <class T, unsigned N>
        class ChecksumTx : public satcat5::io::ChecksumTxCommon {
        public:
            // Implement required API from Writeable:
            unsigned get_write_space() const override {
                // Reserve enough space to append FCS.
                unsigned nbytes = m_dst->get_write_space();
                return (m_ovr || nbytes < N) ? (0) : (nbytes - N);
            }

        protected:
            //! Only the child class has access to the constructor.
            ChecksumTx(satcat5::io::Writeable* dst, T init)
                : ChecksumTxCommon(dst), m_chk(init), m_init(init)
            {
                // Nothing else to initialize
            }

            //! Reset checksum calculation to its initial state.
            void chk_reset() override
                { m_chk = m_init; }

            // Templated internal state:
            T m_chk;                                //!< Checksum state
            const T m_init;                         //!< State after reset
        };

        //! Parent class for non-template elements of ChecksumRx.
        //! This class is not used directly. \see ChecksumRx.
        class ChecksumRxCommon
            : public satcat5::io::CounterSimple
            , public satcat5::io::Writeable {
        public:
            //! Increment the internal error counter.
            //! Some systems use the checksum error counter to consolidate
            //! tracking of multiple frame-error types. \see ccsds_aos.h.
            inline void error_incr()
                { ++m_err_ct; }

            // Implement required API from Writeable:
            unsigned get_write_space() const override;
            void write_abort() override;

        protected:
            //! Only the child class has access to the constructor.
            constexpr explicit ChecksumRxCommon(satcat5::io::Writeable* dst)
                : m_dst(dst) {}

            // Reset the checksum calculation to its initial state.
            // Child MUST implement this method, since data type is unknown.
            virtual void chk_reset() = 0;

            // Internal state:
            satcat5::io::Writeable* const m_dst;    //!< Output object
        };

        //! Check and remove FCS from each incoming frame.
        //! \copydoc io_checksum.h
        //!
        //! Child class is responsible for the following:
        //! * Implement the `chk_reset()` method.
        //! * Implement the `write_next()` method.  This method must
        //!   update the checksum calculation and call `sreg_push()`.
        //! * Implement the `write_finalize()` method.  This method must
        //!   complete the checksum calculation, then call `sreg_match()`,
        //!   then return the resulting pass/fail indicator.
        template <class T, unsigned N>
        class ChecksumRx : public satcat5::io::ChecksumRxCommon {
        protected:
            //! Only the child class has access to the constructor.
            ChecksumRx(satcat5::io::Writeable* dst, T init)
                : ChecksumRxCommon(dst), m_chk(init), m_init(init)
            {
                // Nothing else to initialize.
            }

            //! Reset checksum calculation to its initial state.
            void chk_reset() override
                { m_chk = m_init; }

            //! Child class MUST call sreg_match(...) during write_finalize().
            //! The child provides the FCS in a format that matches SREG.
            inline bool sreg_match(T fcs) {
                // Does the calculated FCS match the last N bytes in SREG?
                constexpr T MASK = satcat5::util::mask_lower<T>(8*N);
                bool ok = (m_frm_len >= N) && ((fcs & MASK) == (m_sreg & MASK));
                // Reset internal state.
                unsigned len = m_frm_len - N;
                m_chk = m_init;
                m_frm_len = 0;
                // Call write_finalize() or write_abort().
                if (ok && m_dst->write_finalize()) {
                    m_byte_ct += len;
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
                if (m_frm_len++ < N) {
                    return false;                   // No update to CRC
                } else {
                    m_dst->write_u8(data);          // Forward popped data
                    return true;                    // Request CRC update
                }
            }

            // Templated internal state:
            T m_chk;                                //!< Checksum state
            const T m_init;                         //!< State after reset
            T m_sreg;                               //!< Big-endian input buffer
        };
    }
}
