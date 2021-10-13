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
// Miscellaneous POSIX wrappers (e.g., heap allocation, log to console...)

#pragma once

#include <satcat5/io_buffer.h>
#include <satcat5/io_core.h>
#include <satcat5/log.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/timer.h>
#include <string>

namespace satcat5 {
    namespace io {
        // Read contents of a SatCat5 buffer as a string.
        std::string read_str(satcat5::io::Readable* src);

        // BufferedWriter with heap allocation.
        class BufferedWriterHeap : public satcat5::io::BufferedWriter {
        public:
            explicit BufferedWriterHeap(
                satcat5::io::Writeable* dst,
                unsigned nbytes = 4096);
            virtual ~BufferedWriterHeap();
        };

        // Packet buffer with heap allocation.
        class PacketBufferHeap : public satcat5::io::PacketBuffer {
        public:
            explicit PacketBufferHeap(unsigned nbytes=4096);
            virtual ~PacketBufferHeap();
        };
    }

    namespace util {
        // Timer object using ctime::clock().
        // (This gives millisecond resolution on most platforms.)
        class PosixTimer : public satcat5::util::GenericTimer {
        public:
            PosixTimer();
            u32 now() override;
        };
    }

    namespace log {
        // Helper object that prints Log messages to console.
        // (Automatically calls log::start on creation and destruction.)
        class ToConsole : public satcat5::log::EventHandler {
        public:
            explicit ToConsole(s8 threshold=satcat5::log::DEBUG);
            virtual ~ToConsole();

            // Disable all output messages until threshold is lowered.
            void disable() {m_threshold = INT8_MAX;}

            // Does the last logged message contain the provided substring?
            bool contains(const char* msg);

            // Other accessors for the last logged message.
            void clear() {m_last_msg.clear();}
            bool empty() {return m_last_msg.empty();}

            // Publically accessible members:
            s8 m_threshold;             // Print only if priority >= threshold
            std::string m_last_msg;     // Most recent message (ignores threshold)

        protected:
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;
            satcat5::util::PosixTimer m_timer;
            u32 m_tref;
        };
    }
}
