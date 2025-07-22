//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Miscellaneous POSIX wrappers (e.g., heap allocation, log to console...)
//! \details
//! For compatibility with microcontrollers, classes in the main "satcat5"
//! folder use a restricted subset of the C/C++ standard library and avoid
//! allocating memory on the heap.  As a result, those classes are sometimes
//! less convenient to use.  This file defines wrappers and extensions for
//! ease of use on platforms that do not require such limitations.  It is
//! compatible with both Linux and Windows platforms.

#pragma once

#include <satcat5/eth_switch.h>
#include <satcat5/io_buffer.h>
#include <satcat5/io_core.h>
#include <satcat5/log.h>
#include <satcat5/multi_buffer.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/timeref.h>
#include <list>
#include <string>
#include <vector>

#ifdef _WIN32
    #define SATCAT5_WIN32 1
#else
    #define SATCAT5_WIN32 0
#endif

namespace satcat5 {
    namespace util {
        //! Helper object for heap allocation.
        class HeapAllocator {
        protected:
            //! Constructor/destructor through child class only.
            explicit HeapAllocator(unsigned nbytes)
                : m_buffptr(new u8[nbytes]) {}
            ~HeapAllocator()
                { delete[] m_buffptr; }

            //! Disable auto-generated assignment and copy methods.
            //!@{
            HeapAllocator(const HeapAllocator&) = delete;
            void operator=(const HeapAllocator&) = delete;
            //!@}

            //! Pointer to the underlying buffer.
            u8* const m_buffptr;
        };
    }

    namespace eth {
        //! Heap-allocated variant of eth::SwitchCore.
        class SwitchCoreHeap final
            : public satcat5::util::HeapAllocator
            , public satcat5::eth::SwitchCore {
        public:
            explicit SwitchCoreHeap(unsigned nbytes = 65536);
        };
    }

    namespace io {
        //! Read contents of a SatCat5 buffer as a string.
        std::string read_str(satcat5::io::Readable* src);

        //! BufferedTee copies incoming data to any number of destinations.
        class BufferedTee
            : public satcat5::util::HeapAllocator
            , public satcat5::io::ArrayWrite {
        public:
            //! Create this object and set its buffer size.
            explicit BufferedTee(unsigned nbytes = 4096);

            //! Update the list of destination objects.
            inline void add(satcat5::io::Writeable* dst)
                { m_list.push_back(dst); }
            inline void remove(satcat5::io::Writeable* dst)
                { m_list.remove(dst); }

            //! Override end-of-packet handling.
            bool write_finalize() override;

        protected:
            std::list<satcat5::io::Writeable*> m_list;
        };

        //! BufferedWriter with heap allocation.
        class BufferedWriterHeap final
            : public satcat5::util::HeapAllocator
            , public satcat5::io::BufferedWriter {
        public:
            explicit BufferedWriterHeap(
                satcat5::io::Writeable* dst,
                unsigned nbytes = 4096);
        };

        //! Stream keyboard input to a Writeable interface.
        class KeyboardStream : public satcat5::poll::Always {
        public:
            explicit KeyboardStream(
                satcat5::io::Writeable* dst,
                bool line_buffer = true);
            virtual ~KeyboardStream();

        protected:
            void poll_always() override;
            void write_key(int ch);
            satcat5::io::Writeable* const m_dst;
            const bool m_line_buffer;
        };

        //! MultiBuffer with heap allocation.
        class MultiBufferHeap
            : public satcat5::util::HeapAllocator
            , public satcat5::io::MultiBuffer {
        public:
            explicit MultiBufferHeap(unsigned nbytes=65536);
            virtual ~MultiBufferHeap() {}
        };

        //! PacketBuffer with heap allocation (in packet mode).
        class PacketBufferHeap final
            : public satcat5::util::HeapAllocator
            , public satcat5::io::PacketBuffer {
        public:
            explicit PacketBufferHeap(unsigned nbytes=4096);
        };

        //! PacketBuffer with optional wiretap(s).
        //! Reads and writes go to the buffer. If additional ports are
        //! added, then each gets a carbon-copy of all written data.
        class PacketBufferTee final
            : public satcat5::io::ReadableRedirect
            , public satcat5::io::BufferedTee {
        public:
            explicit PacketBufferTee(unsigned nbytes=4096);
            inline void clear() {m_buff.clear();}
        protected:
            satcat5::io::PacketBufferHeap m_buff;
        };

        //! PacketBuffer with heap allocation (in stream mode).
        //! (As PacketBufferHeap, but ignores packet boundaries.)
        class StreamBufferHeap final
            : public satcat5::util::HeapAllocator
            , public satcat5::io::PacketBuffer {
        public:
            explicit StreamBufferHeap(unsigned nbytes=4096);
        };

        //! PacketBuffer with optional wiretap(s).
        //! Reads and writes go to the buffer. If additional ports are
        //! added, then each gets a carbon-copy of all written data.
        class StreamBufferTee final
            : public satcat5::io::ReadableRedirect
            , public satcat5::io::BufferedTee {
        public:
            explicit StreamBufferTee(unsigned nbytes=4096);
            inline void clear() {m_buff.clear();}
        protected:
            satcat5::io::StreamBufferHeap m_buff;
        };
    }

    namespace util {
        //! Timer object using ctime::clock().
        //! This gives millisecond resolution on most platforms.
        class PosixTimer : public satcat5::util::TimeRef {
        public:
            PosixTimer();
            u32 raw() override;         // Monotonic millisecond counter
            s64 gps() const;            // Milliseconds since GPS epoch
        };

        //! Link a PosixTimer to the main polling timekeeper.
        //! Most POSIX designs should have a global instance of this object.
        class PosixTimekeeper {
        public:
            PosixTimekeeper();
            virtual ~PosixTimekeeper();

            inline s64 gps()        {return m_timer.gps();}
            inline TimeVal now()    {return m_timer.now();}
            inline u32 raw()        {return m_timer.raw();}

            satcat5::util::TimeRef* timer() {return &m_timer;}

        protected:
            satcat5::util::PosixTimer m_timer;
            satcat5::irq::VirtualTimer m_adapter;
        };

        //! Cross-platform wrapper for sleep()/Sleep()/etc.
        void sleep_msec(unsigned msec);

        //! Alternate between sleep_msec() and poll::service_all().
        void service_msec(unsigned total_msec, unsigned msec_per_iter = 10);
    }

    namespace log {
        //! Human-readable formatting for an Ethernet address.
        std::string format(const satcat5::eth::MacAddr& addr);
        //! Human-readable formatting for an IPv4 address.
        std::string format(const satcat5::ip::Addr& addr);

        //! Helper object that prints log::Log messages to console.
        //! Automatically calls log::start on creation and destruction.
        //! Stores the most recent log message, to facilitate unit tests.
        class ToConsole final : public satcat5::log::EventHandler {
        public:
            //! On creation, optionally specify the minimum priority to print.
            explicit ToConsole(s8 threshold=satcat5::log::DEBUG);

            //! Disable all output messages until threshold is lowered.
            void disable() {m_threshold = INT8_MAX;}

            //! Suppress messages containing a specific string.
            //! Filters are added to an internal list; null pointer clears the list.
            void suppress(const char* msg);

            //! Does the last logged message contain the provided substring?
            bool contains(const char* msg);

            //! Clear the stored copy of the most recent log message.
            void clear() {m_last_msg.clear();}
            //! Is there a stored log message?
            bool empty() {return m_last_msg.empty();}

            // Publically accessible members:
            s8 m_threshold;             //!< Print only if priority >= threshold
            std::string m_last_msg;     //!< Most recent message (ignores threshold)

        protected:
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;
            std::vector<std::string> m_suppress;
            satcat5::util::PosixTimer m_timer;
            satcat5::util::TimeVal m_tref;
        };
    }
}
