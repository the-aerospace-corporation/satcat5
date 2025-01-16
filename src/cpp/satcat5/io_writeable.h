//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! "Writeable" I/O interface core definitions
//!
//! \details
//! The core of all SatCat5 I/O are the "Writeable" interface (io_writeable.h)
//! and "Readable" interface (io_readable.h).  These general-purpose virtual
//! interfaces are used by PacketBuffer, generic UARTs, etc. for code reuse.

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace io {
        //! Abstract API for writing byte-streams and packets.
        //! The abstract `Writeable` interface is for writing data to a device
        //! or buffer. Anything that accepts a byte-stream, with or without
        //! packets, should usually implement this interface to allow flexible
        //! reconnection with other SatCat5 tools.
        class Writeable {
        public:
            //! How many bytes can be written without blocking?
            //!
            //! Child objects of io::Writeable MUST override this method.
            virtual unsigned get_write_space() const = 0;

            // Write various data types in big-endian format.
            //! One of many functions for writing integer/floating point values,
            //! see details.
            //!
            //! Several functions are provided for reading and writing scalar
            //! types to/from io::Readable and io::Writeable instances. Since
            //! there are many of these that are frequently inherited, they are
            //! hidden from documentation. These functions follow a shared
            //! template:
            //!
            //!  * `read_` or `write_` prefix.
            //!  * `u` for unsigned, `s` for signed, `f` for floating-point.
            //!  * Data-type width in bits.
            //!    * Available widths for ints: 8/16/24/32/48/64.
            //!    * Available widths for floats: 32/64.
            //!  * `l` suffix if little-endian, no suffix if big-endian.
            //!
            //! Example: `write_s48l` is "Write 48 bits (6 bytes) to this
            //! io::Writeable as a signed value in little-endian order".
            void write_u8(u8 data);
            //! \cond io_int_render
            void write_u16(u16 data);
            void write_u24(u32 data);
            void write_u32(u32 data);
            void write_u48(u64 data);
            void write_u64(u64 data);
            void write_s8(s8 data);
            void write_s16(s16 data);
            void write_s24(s32 data);
            void write_s32(s32 data);
            void write_s48(s64 data);
            void write_s64(s64 data);
            void write_f32(float data);
            void write_f64(double data);

            // Write various data types in little-endian format.
            void write_u16l(u16 data);
            void write_u24l(u32 data);
            void write_u32l(u32 data);
            void write_u48l(u64 data);
            void write_u64l(u64 data);
            void write_s16l(s16 data);
            void write_s24l(s32 data);
            void write_s32l(s32 data);
            void write_s48l(s64 data);
            void write_s64l(s64 data);
            void write_f32l(float data);
            void write_f64l(double data);
            //! \endcond

            //! Write 0 or more bytes from a buffer.
            //! Child objects of io::Writeable MAY override `write_bytes` as
            //! needed for performance.
            virtual void write_bytes(unsigned nbytes, const void* src);

            //! Write the contents of a null-terminated string.
            //! Note: Null-termination is not copied to the output.
            void write_str(const char* str);

            //! Mark end of frame and release temporary working data.
            //! Child objects of io::Writeable SHOULD override this method to
            //! mark frame bounds.
            //! \returns True if successful, false on error.
            virtual bool write_finalize();

            //! If possible, abort the current partially-written packet.
            //! Child objects of io::Writeable SHOULD override this method if it
            //! is practical to prevent in-progress data from being relayed
            //! downstream.
            virtual void write_abort();

            //! Templated wrapper for any object with the following method:
            //! `void write_to(satcat5::io::Writeable* wr) const;`
            template <class T> inline void write_obj(const T& obj)
                {obj.write_to(this);}

        protected:
            friend LimitedWrite;
            friend WriteableRedirect;

            //! Only children should create or destroy the base class.
            constexpr Writeable() {}
            ~Writeable() {}

            //! Write the next byte to the underlying buffer or device.
            //! Child objects of io::Writeable MUST override this method.
            virtual void write_next(u8 data) = 0;

            //! Optional error handling for write overflow.
            //! Child objects of io::Writeable MAY override this method for
            //! error handling.
            virtual void write_overflow();
        };

        //! Ephemeral `Writeable` interface for a simple array.
        class ArrayWrite : public satcat5::io::Writeable {
        public:
            //! Create an ArrayWrite object linked to the provided working
            //! buffer.
            //!
            //! For ease of use, constructor accepts dst/length or length/dst.
            //!@{
            constexpr ArrayWrite(void* dst, unsigned len)
                : m_dst((u8*)dst), m_len(len), m_ovr(false), m_wridx(0), m_wrlen(0) {}
            constexpr ArrayWrite(unsigned len, void* dst)
                : m_dst((u8*)dst), m_len(len), m_ovr(false), m_wridx(0), m_wrlen(0) {}
            //!@}

            // Implement the public Readable API.
            unsigned get_write_space() const override;
            void write_abort() override;
            bool write_finalize() override;
            void write_overflow() override;

            //! Read-only access to the working buffer.
            const u8* buffer() const
                { return m_dst; }

            //! Report total length after write_finalize() is called.
            inline unsigned written_len() const
                { return m_wrlen; }

        private:
            // Implement the private Writeable API.
            void write_next(u8 data) override;

            // Internal state.
            u8* const       m_dst;
            const unsigned  m_len;
            bool            m_ovr;
            unsigned        m_wridx;
            unsigned        m_wrlen;
        };

        //! Thin wrapper for ArrayWrite with a built-in buffer.
        //! Equivalent to `u8 tmp[SIZE]; ArrayWrite wr(tmp, sizeof(tmp));`
        template <unsigned SIZE>
        class ArrayWriteStatic : public satcat5::io::ArrayWrite {
        public:
            constexpr ArrayWriteStatic()
                : ArrayWrite(m_buff, SIZE), m_buff{} {}
        private:
            u8 m_buff[SIZE];
        };

        //! Limited write up to N bytes.  Does not forward write_finalize().
        //!
        //! This class is used to limit the number of bytes that can be
        //! written to a target destination.
        //!
        //! LimitedWrite does nothing when write_finalize() is called.
        class LimitedWrite : public satcat5::io::Writeable {
        public:
            //! Explicitly set maximum write length in bytes.
            //!
            //! For ease of use, constructor accepts src/length or length/src.
            //!@{
            constexpr LimitedWrite(satcat5::io::Writeable* dst, unsigned maxwr)
                : m_dst(dst), m_rem(maxwr) {}
            constexpr LimitedWrite(unsigned maxwr, satcat5::io::Writeable* dst)
                : m_dst(dst), m_rem(maxwr) {}
            //!@}

            unsigned get_write_space() const override;
            void write_bytes(unsigned nbytes, const void* src) override;

        protected:
            // Implement the private Writeable API.
            void write_next(u8 data) override;

        private:
            satcat5::io::Writeable* const m_dst;
            unsigned m_rem;
        };

        //! Wrapper class for forwarding writes to another object.
        //! This class is used to add a Writeable interface to an object
        //! by forwarding all API calls to another object.
        //!
        //! An example usage is a UART driver. From a user's perspective,
        //! outgoing data is written to the UART. Using WriteableRedirect,
        //! the UART driver can forward that data to a software FIFO
        //! object, then copy data from the FIFO to the UART hardware.
        //!
        //! To use this class, create a new class that inherits from
        //! WriteableRedirect. The constructor sets the forwarding address.
        class WriteableRedirect : public satcat5::io::Writeable {
        public:
            unsigned get_write_space() const override;
            void write_abort() override;
            void write_bytes(unsigned nbytes, const void* src) override;
            bool write_finalize() override;
        protected:
            explicit constexpr WriteableRedirect(satcat5::io::Writeable* dst)
                : m_dst(dst) {}
            ~WriteableRedirect() {}
            void write_next(u8 data) override;
            void write_overflow() override;
            inline void write_dst(satcat5::io::Writeable* dst) {m_dst = dst;}
        private:
            satcat5::io::Writeable* m_dst;
        };

        //! Writeable object that accepts and discards all incoming data.
        class NullWrite : public satcat5::io::Writeable {
        public:
            explicit constexpr NullWrite(unsigned wspace)
                : m_write_space(wspace) {}
            unsigned get_write_space() const override;
            void write_bytes(unsigned nbytes, const void* src) override;
        private:
            void write_next(u8 data) override;
            const unsigned m_write_space;
        };

        //! Global instance of the basic NullWrite object.
        //! Use this placeholder instead of a null pointer.
        extern satcat5::io::NullWrite null_write;
    }
}
