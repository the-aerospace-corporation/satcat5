//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! "Readable" I/O interface core definitions
//!
//! \details
//! The core of all SatCat5 I/O are the "Writeable" interface (io_writeable.h)
//! and "Readable" interface (io_readable.h).  These general-purpose virtual
//! interfaces are used by PacketBuffer, generic UARTs, etc. for code reuse.

#pragma once

#include <satcat5/polling.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace io {
        //! Event-handler interface for newly received data.
        //! (i.e., The callback notification for the `Readable` interface.)
        //! Note: EventListeners that call `set_callback(this)` in their
        //!  constructor must call `set_callback(0)` in their destructor,
        //!  unless the source is destroyed. See data_unlink(...).
        class EventListener {
        public:
            //! The data_rcvd() callback is polled whenever data is available.
            //! A pointer is provided to assist handlers with multiple sources.
            //! Child objects of io::EventListener MUST override this method.
            virtual void data_rcvd(satcat5::io::Readable* src) = 0;

            //! Unlink this EventListener from the designated source,
            //! because the designated Readable object is being destroyed.
            //! Child objects of io::EventListener MAY override this method if
            //! action is required.
            virtual void data_unlink(satcat5::io::Readable* src) {}

        protected:
            ~EventListener() {}
        };

        //! Abstract API for reading byte-streams and packets.
        //! The abstract `Readable` interface is for reading data from a device
        //! or buffer. Anything that provides a byte-stream, with or without
        //! packets, should usually implement this interface to allow flexible
        //! reconnection with other SatCat5 tools.
        //!
        //! Note: If frame boundaries are supported, `read_*` methods MUST NOT
        //!       read past the boundary until read_finalize() is called.
        class Readable : public satcat5::poll::OnDemand {
        public:
            //! Update registered callback for data_rcvd() events.
            //! Child objects of io::Readable SHOULD usually leave this method
            //! as-is.
            virtual void set_callback(satcat5::io::EventListener* callback);

            //! How many bytes can be read without blocking?
            //!
            //! Child objects of io::Readable MUST override this method.
            virtual unsigned get_read_ready() const = 0;

            // Read various data types in big-endian format.
            //! One of many functions for reading integer/floating point values,
            //! see details.
            //! \copydetails io::Writeable::write_u8()
            u8 read_u8();
            //! \cond io_int_render
            // Triggers Doxygen warnings about missing docs, can we suppress?
            u16 read_u16();
            u32 read_u24();
            u32 read_u32();
            u64 read_u48();
            u64 read_u64();
            s8 read_s8();
            s16 read_s16();
            s32 read_s24();
            s32 read_s32();
            s64 read_s48();
            s64 read_s64();
            float read_f32();
            double read_f64();

            // Read various data types in little-endian format.
            u16 read_u16l();
            u32 read_u24l();
            u32 read_u32l();
            u64 read_u48l();
            u64 read_u64l();
            s16 read_s16l();
            s32 read_s24l();
            s32 read_s32l();
            s64 read_s48l();
            s64 read_s64l();
            float read_f32l();
            double read_f64l();
            //! \endcond

            //! Read 0 or more bytes into a buffer.
            //! Child objects of io::Readable MAY override this method for
            //! improved performance.
            virtual bool read_bytes(unsigned nbytes, void* dst);

            //! Read and discard 0 or more bytes.
            //! Child objects of io::Readable MAY override this method for
            //! improved performance.
            virtual bool read_consume(unsigned nbytes);

            //! Safely read a null-terminated input string.
            //! The input is always consumed up to the end-of-input or the
            //! first zero byte, whichever comes first.
            //! \returns The length of the output string, which may
            //! be truncated as needed to fit in the provided buffer.
            unsigned read_str(unsigned dst_size, char* dst);

            //! Consume any remaining bytes in this frame, if applicable.
            //! Child objects of io::Readable SHOULD override this method if
            //! they support framing.
            virtual void read_finalize();

            //! Templated wrapper for any object with the following method:
            //! `bool read_from(satcat5::io::Readable* rd);`
            template <class T> inline bool read_obj(T& t)
                {return t.read_from(this);}

            //! Copy stream contents to a Writeable object, up to end-of-frame
            //! or buffer limit.
            //! \returns The number of bytes copied.
            unsigned copy_to(satcat5::io::Writeable* dst);

            //! As copy_to (see above), but also calls read_finalize() and
            //! write_finalize() if the operation copies all available data.
            //! \returns True if the output was finalized successfully.
            bool copy_and_finalize(satcat5::io::Writeable* dst);

        protected:
            friend satcat5::io::LimitedRead;
            friend satcat5::io::ReadableRedirect;

            //! Only children should create or destroy the base class.
            explicit constexpr Readable(satcat5::io::EventListener* callback = 0)
                : m_callback(callback) {}
            ~Readable() SATCAT5_OPTIONAL_DTOR;

            //! Read the next byte from the underlying buffer or device.
            //! Child objects of io::Readable MUST override this method.
            virtual u8 read_next() = 0;

            //! Attempt notification by calling `m_callback->data_rcvd()`.
            //! Child objects of io::Readable MAY call this to override default
            //! notifications.
            void read_notify();

            //! Optional error handling for read underflow.
            //! Child objects of io::Readable MAY override this method.
            virtual void read_underflow();

        private:
            //! Event handler for on-demand polling.
            void poll_demand();

            //! Pointer to the callback object, or NULL.
            //! This can only be modified through the set_callback(...) method.
            satcat5::io::EventListener* m_callback;
        };

        //! Ephemeral `Readable` interface for a simple array.
        //! This class can be used to parse structured data from a byte-array,
        //! or to pass byte-array data to a SatCat5 object that requires the
        //! `Readable` API.  It does not take ownership of the backing array.
        class ArrayRead : public satcat5::io::Readable {
        public:
            //! For ease of use, constructor accepts src/length or length/src.
            //!@{
            constexpr ArrayRead(const void* src, unsigned len)
                : m_src((const u8*)src), m_len(len), m_rdidx(0) {}
            constexpr ArrayRead(unsigned len, const void* src)
                : m_src((const u8*)src), m_len(len), m_rdidx(0) {}
            //!@}

            // Implement the public Readable API.
            unsigned get_read_ready() const override;
            void read_finalize() override;

            //! Reset read position to the start of the backing array,
            //! and set the readable length to the specified value.
            void read_reset(unsigned len);

        private:
            // Implement the private Readable API.
            u8 read_next() override;
            const u8* const m_src;

            // Internal state.
            unsigned m_len;     // Length of the backing array
            unsigned m_rdidx;   // Current read position
        };

        //! Limited read of next N bytes.  Does not forward read_finalize().
        //!
        //! This class is used to read a controlled amount from a longer
        //! input.  For example, it can be used to read one block from
        //! a file containing a series of length/data pairs, or to read one
        //! sub-field from the body of a longer packet.
        //!
        //! LimitedRead will advance the read-position of the source `Readable`
        //! object, but never reads further than the designated limit.  Calling
        //! read_finalize() advances the source's read-position to the end of
        //! the designated limit, but does not forward a read_finalize() call
        //! to the source object.
        class LimitedRead : public satcat5::io::Readable {
        public:
            //! Explicitly set maximum read length in bytes.
            //!
            //! For ease of use, constructor accepts src/length or length/src.
            //!@{
            constexpr LimitedRead(satcat5::io::Readable* src, unsigned maxrd)
                : m_src(src), m_rem(maxrd) {}
            constexpr LimitedRead(unsigned maxrd, satcat5::io::Readable* src)
                : m_src(src), m_rem(maxrd) {}
            //!@}

            //! Automatically set read length based on src->get_read_ready()
            explicit LimitedRead(satcat5::io::Readable* src);

            // Implement the public Readable API.
            unsigned get_read_ready() const override;
            bool read_bytes(unsigned nbytes, void* dst) override;
            bool read_consume(unsigned nbytes) override;
            void read_finalize() override;

        protected:
            // Implement the private Readable API.
            u8 read_next() override;

            //! Children may reset the number of remaining bytes.
            inline void read_reset(unsigned rem) {m_rem = rem;}

        private:
            satcat5::io::Readable* const m_src;
            unsigned m_rem;
        };

        //! Wrapper class for forwarding reads to another object.
        //! This class is used to add a Readable interface to an object
        //! by forwarding all API calls to another object.
        //!
        //! An example usage is a UART driver. From a user's perspective,
        //! incoming data is read from the UART. Using ReadableRedirect,
        //! the UART driver can copy data from the UART hardware to a
        //! software FIFO, then allow the user to read from that FIFO.
        //!
        //! To use this class, create a new class that inherits from
        //! ReadableRedirect. The constructor sets the forwarding address.
        class ReadableRedirect : public satcat5::io::Readable {
        public:
            // Implement the public Readable API.
            void set_callback(satcat5::io::EventListener* callback) override;
            unsigned get_read_ready() const override;
            bool read_bytes(unsigned nbytes, void* dst) override;
            bool read_consume(unsigned nbytes) override;
            void read_finalize() override;

        protected:
            //! Constructor and destructor should only be called by the child.
            explicit constexpr ReadableRedirect(satcat5::io::Readable* src)
                : m_src(src) {}
            ~ReadableRedirect() {}

            // Implement the private Readable API.
            u8 read_next() override;
            void read_underflow() override;

            //! Children may reset the source object as needed.
            inline void read_src(satcat5::io::Readable* src) {m_src = src;}

        private:
            satcat5::io::Readable* m_src;
        };


        //! Readable object that never produces any data.
        class NullRead : public satcat5::io::Readable {
        public:
            NullRead() {}
            unsigned get_read_ready() const override;
        private:
            u8 read_next() override;
        };

        //! An EventListener object that immediately discards all received data.
        class NullSink : public satcat5::io::EventListener {
            void data_rcvd(satcat5::io::Readable* src) override;
        };

        //! Global instances of the basic NullRead and NullSink objects.
        //!
        //! Use these placeholders instead of null pointers.  e.g., Any number
        //! of sources may call `my_src.set_callback(&satcat5::io::null_sink);`
        //!@{
        extern satcat5::io::NullRead null_read;
        extern satcat5::io::NullSink null_sink;
        //!@}
    }
}
