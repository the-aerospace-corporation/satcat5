//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Writeable API that broadcasts copies to multiple destinations.
//!
//!\details
//! The io::WriteableBroadcast object implements the io::Writeable API
//! and tracks an array of downstream io::Writeable objects.  When any
//! data is written, the object broadcasts copies of that data to each
//! downstream object.
//!
//! Memory allocation is left to the child object. The simplest option
//! is io::WriteableBroadcastStatic, which uses a templated static array.
//!

#pragma once

#include <satcat5/io_writeable.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace io {
        //! Forwards incoming writes to multiple downstream Writeables.
        //!
        //! Constructor takes an array of io::Writeable pointers. These may or
        //! may not be NULL, and can be (re-)set at runtime via `port_set()`
        //! or the array-index operator (i.e., my_object[n]).
        //!
        //! When written to via the io::Writeable API, writes are copied to all
        //! non-NULL destinations in the array. Finalize is called on each array
        //! element and returns true only if every non-null Writeable's finalize
        //! call was successful.
        class WriteableBroadcast : public satcat5::io::Writeable {
        public:
            // Implement the public Writeable API.
            unsigned get_write_space() const override;
            void write_abort() override;
            void write_bytes(unsigned nbytes, const void* src) override;
            bool write_finalize() override;

            //! Access or assign the Nth downstream Writeable object.
            Writeable*& operator[](unsigned idx)
                { return m_dsts[idx]; }

            //! Designate the Nth downstream Writeable object.
            void port_set(unsigned idx, Writeable* dst)
                { if (idx < m_size) { m_dsts[idx] = dst; } }

            //! Length of the output array.
            inline unsigned len() const
                { return m_size; }

        protected:
            //! Constructor takes a pointer to an array of io::Writeable
            //! pointers along with the length of the given array.
            constexpr WriteableBroadcast(unsigned n_dsts,
                    satcat5::io::Writeable** dsts)
                : m_size(n_dsts), m_dsts(dsts) {}
            ~WriteableBroadcast() {}
            void write_next(u8 data) override;
            void write_overflow() override;
        private:
            // Member variables.
            const unsigned m_size;                  //!< Size of `m_dsts`.
            satcat5::io::Writeable** const m_dsts;  //!< Array of Writeables.
        };

        //! Statically-allocated version of io::WriteableBroadcast.
        template <unsigned SIZE>
        class WriteableBroadcastStatic final
            : public satcat5::io::WriteableBroadcast {
        public:
            WriteableBroadcastStatic()
                : WriteableBroadcast(SIZE, m_dst_array), m_dst_array{0} {}
        private:
            satcat5::io::Writeable* m_dst_array[SIZE];
        };
    }
}