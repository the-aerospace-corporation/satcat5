//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// "Readable" I/O interface core definitions
//
// Define the abstract "Readable" interface. Anything that provides a
// byte-stream, with or without packets, should usually implement this
// interface to allow flexiable reconnection with other SatCat5 tools.
//

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

        // Generic interface for reading data from a device or buffer.
        class Readable : public satcat5::poll::OnDemand {
        public:
            // Update registered callback for data_rcvd() events.
            // (Child objects SHOULD usually leave this method as-is.)
            virtual void set_callback(satcat5::io::EventListener* callback);

            // How many bytes can be read without blocking?
            // (Child objects MUST override this method.)
            virtual unsigned get_read_ready() const = 0;

            // Read various data types in big-endian format.
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

            // Read various data types in little-endian format.
            u16 read_u16l();
            u32 read_u32l();
            u64 read_u64l();
            s16 read_s16l();
            s32 read_s32l();
            s64 read_s64l();
            float read_f32l();
            double read_f64l();

            // Safely read a null-terminated input string.
            // Return value is the length of the output string, which may
            // be truncated as needed to fit in the provided buffer.
            // The input is always consumed up to the end-of-input or the
            // first zero byte, whichever comes first.
            unsigned read_str(unsigned dst_size, char* dst);

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

            // Attempt notification by calling "m_callback->data_rcvd()".
            // Returns true if a callback is configured and data is available.
            // (Child objects may call this to override default notifications.)
            void read_notify();

            // Optional error handling for read underflow.
            // (Child objects may override this method.)
            virtual void read_underflow();

        private:
            // Event handler for on-demand polling.
            void poll_demand();

            // Pointer to the callback object, or NULL.
            satcat5::io::EventListener* m_callback;
        };

        // Ephermeral "Readable" interface for a simple array.
        class ArrayRead : public satcat5::io::Readable {
        public:
            ArrayRead(const void* src, unsigned len);
            unsigned get_read_ready() const override;
            void read_finalize() override;
            void read_reset(unsigned len);
        private:
            u8 read_next() override;
            const u8* const m_src;
            unsigned m_len;
            unsigned m_rdidx;
        };

        // Limited read of next N bytes.  Does not forward read_finalize().
        class LimitedRead : public satcat5::io::Readable {
        public:
            // Explicitly set maximum read length in bytes.
            LimitedRead(satcat5::io::Readable* src, unsigned maxrd);
            // Automatically set read length based on src->get_read_ready()
            explicit LimitedRead(satcat5::io::Readable* src);
            unsigned get_read_ready() const override;
            bool read_bytes(unsigned nbytes, void* dst) override;
            bool read_consume(unsigned nbytes) override;
        private:
            u8 read_next() override;
            satcat5::io::Readable* const m_src;
            unsigned m_rem;
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
            inline void read_src(satcat5::io::Readable* src) {m_src = src;}
        private:
            satcat5::io::Readable* m_src;
        };
    }
}
