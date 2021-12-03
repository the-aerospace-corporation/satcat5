//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// I/O interface core definitions
//
// Define the abstract "Writeable" and "Readable" interfaces that are
// used by PacketBuffer, generic UARTs, etc. for code reuse.

#pragma once

#include <satcat5/polling.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace io {
        // Event-handler interface for newly received data.
        // (i.e., The callback notification for the "Readable" interface.)
        class EventListener {
        public:
            // (Child objects MUST override this method.)
            virtual void data_rcvd() = 0;
        protected:
            ~EventListener() {}
        };

        // Generic interface for writing data to a device or buffer.
        class Writeable {
        public:
            // How many bytes can be written without blocking?
            // (Child objects MUST override this method.)
            virtual unsigned get_write_space() const = 0;

            // Write various data types.
            // (Child MAY override "write_bytes" as needed for performance.)
            void write_u8(u8 data);
            void write_u16(u16 data);
            void write_u32(u32 data);
            void write_u64(u64 data);
            void write_s8(s8 data);
            void write_s16(s16 data);
            void write_s32(s32 data);
            void write_s64(s64 data);
            void write_f32(float data);
            void write_f64(double data);
            void write_str(const char* str);
            virtual void write_bytes(unsigned nbytes, const void* src);

            // Mark end of frame and release temporary working data.
            // Returns true if successful, false on error.
            // (Child objects SHOULD override this method to mark frame bounds.)
            virtual bool write_finalize();

            // If possible, abort the current partially-written packet.
            // (Child objects SHOULD override this method if it is practical
            //  to prevent in-progress data from being relayed downstream.)
            virtual void write_abort();

            // Templated wrapper for any object with the following method:
            //  void write_to(satcat5::io::Writeable* wr) const;
            template <class T> inline void write_obj(const T& obj)
                {obj.write_to(this);}

        protected:
            friend WriteableRedirect;

            // Only children should create or destroy the base class.
            Writeable() {}
            ~Writeable() {}

            // Write the next byte to the underlying buffer or device.
            // (Child objects MUST override this method.)
            virtual void write_next(u8 data) = 0;

            // Optional error handling for write overflow.
            // (Child objects MAY override this method for error handling.)
            virtual void write_overflow();
        };

        // Generic interface for reading data from a device or buffer.
        class Readable : public satcat5::poll::OnDemand {
        public:
            // Update registered callback for data_rcvd() events.
            // (Child objects SHOULD usually leave this method as-is.)
            virtual void set_callback(satcat5::io::EventListener* callback);

            // How many bytes can be read without blocking?
            // (Child objects MUST override this method.)
            virtual unsigned get_read_ready() const = 0;

            // Read various data types.
            // Note: If frame boundaries are supported, these methods MUST not
            //       read past the boundary until read_finalize() is called.
            // (Child MAY override "read_bytes" and "read_consume" for improved
            //  performance of very long read operations.)
            u8 read_u8();
            u16 read_u16();
            u32 read_u32();
            u64 read_u64();
            s8 read_s8();
            s16 read_s16();
            s32 read_s32();
            s64 read_s64();
            float read_f32();
            double read_f64();
            virtual bool read_bytes(unsigned nbytes, void* dst);
            virtual bool read_consume(unsigned nbytes);

            // Consume any remaining bytes in this frame, if applicable.
            // (Child objects SHOULD override this method if they support framing.)
            virtual void read_finalize();

            // Templated wrapper for any object with the following method:
            //  bool read_from(satcat5::io::Readable* rd);
            template <class T> inline bool read_obj(T& t)
                {return t.read_from(this);}

            // Copy stream contents to a Writeable object, up to end-of-frame
            // or buffer limit.  Returns true if this exhausts the input.
            // (i.e., Caller should read_finalize() and/or write_finalize().)
            bool copy_to(satcat5::io::Writeable* dst);

        protected:
            friend satcat5::io::LimitedRead;
            friend satcat5::io::ReadableRedirect;

            // Only children should create or destroy the base class.
            explicit Readable(satcat5::io::EventListener* callback = 0);
            ~Readable() {}

            // Read the next byte from the underlying buffer or device.
            // (Child objects MUST override this method.)
            virtual u8 read_next() = 0;

            // Optional error handling for read underflow.
            // (Child objects may override this method.)
            virtual void read_underflow();

        private:
            // Event handler for on-demand polling.
            void poll_demand();

            // Pointer to the callback object, or NULL.
            satcat5::io::EventListener* m_callback;
        };

        // Ephemeral "Writeable" interface for a simple array.
        class ArrayWrite : public satcat5::io::Writeable {
        public:
            ArrayWrite(void* dst, unsigned len);
            unsigned get_write_space() const override;
            bool write_finalize() override;
            inline unsigned written_len() const {return m_wrlen;}
        private:
            void write_next(u8 data) override;
            u8* const       m_dst;
            const unsigned  m_len;
            unsigned        m_wridx;
            unsigned        m_wrlen;
        };

        // Ephermeral "Readable" interface for a simple array.
        class ArrayRead : public satcat5::io::Readable {
        public:
            ArrayRead(const void* src, unsigned len);
            unsigned get_read_ready() const override;
            void read_finalize() override;
        private:
            u8 read_next() override;
            const u8* const m_src;
            const unsigned  m_len;
            unsigned        m_rdidx;
        };

        // Limited read of next N bytes.  Does not forward read_finalize().
        class LimitedRead : public satcat5::io::Readable {
        public:
            LimitedRead(satcat5::io::Readable* src, unsigned maxrd);
            unsigned get_read_ready() const override;
            bool read_bytes(unsigned nbytes, void* dst) override;
            bool read_consume(unsigned nbytes) override;
        private:
            u8 read_next() override;
            satcat5::io::Readable* const m_src;
            unsigned m_rem;
        };

        // Wrapper class used to gain indirect access to "Writeable::write_next"
        // method, which is required for certain types of I/O adapters.
        class WriteableRedirect : public satcat5::io::Writeable {
        public:
            unsigned get_write_space() const override;
            void write_bytes(unsigned nbytes, const void* src) override;
            bool write_finalize() override;
        protected:
            explicit WriteableRedirect(satcat5::io::Writeable* dst);
            ~WriteableRedirect() {}
            void write_next(u8 data) override;
            void write_overflow() override;
        private:
            satcat5::io::Writeable* const m_dst;
        };

        // Wrapper class used to gain indirect access to "Readable::read_next"
        // method, which is required for certain types of I/O adapters.
        class ReadableRedirect : public satcat5::io::Readable {
        public:
            void set_callback(satcat5::io::EventListener* callback) override;
            unsigned get_read_ready() const override;
            bool read_bytes(unsigned nbytes, void* dst) override;
            bool read_consume(unsigned nbytes) override;
            void read_finalize() override;
        protected:
            explicit ReadableRedirect(satcat5::io::Readable* src);
            ~ReadableRedirect() {}
            u8 read_next() override;
            void read_underflow() override;
        private:
            satcat5::io::Readable* const m_src;
        };
    }
}
