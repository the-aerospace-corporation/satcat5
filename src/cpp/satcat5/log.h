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
// Diagnostic logging to UART and/or Ethernet ports
//
// Log objects are used for diagnostic logging, with a few simple
// formatting options.  It is intended for simple debugging while
// being much lighter-weight than printf().
//
// The Log object is ephemeral, with chaining for readable syntax.
// Each of the three examples below produces the same message:
//
//      using satcat5::log::Log;
//
//      void example1(u8 errcode) {
//          Log(satcat5::log::WARNING, "Oh noooo").write(errcode);
//      }
//
//      void example2(u8 errcode) {
//          Log(satcat5::log::WARNING).write("Oh noooo").write(errcode);
//      }
//
//      void example3(u8 errcode) {
//          Log log(satcat5::log::WARNING);
//          log.write("Oh noooo");
//          log.write(errcode);
//      }
//
// Message contents are written to the globally-specified event-handler
// when the Log object falls out of scope.  Call log_start() to set
// or reset the event-handler object.
//

#pragma once

#include <satcat5/types.h>

// Default parameters:
#ifndef SATCAT5_LOG_MAXLEN      // Maximum string length per message
#define SATCAT5_LOG_MAXLEN  255
#endif

#ifndef SATCAT5_LOG_CONCISE     // Enable concise syntax?
#define SATCAT5_LOG_CONCISE 1
#endif

namespace satcat5 {
    namespace log {
        // Define the interface for accepting Log messages.
        class EventHandler {
        public:
            // (Child class must override this method.)
            virtual void log_event(s8 priority, unsigned nbytes, const char* msg) = 0;
        protected:
            ~EventHandler() {}
        };

        // Basic LogEventHandler that copies contents to a UART or similar.
        // (And optionally carbon-copies the data to a second handler.)
        // Note: This object's constructor automatically calls log_start().
        class ToWriteable final : public satcat5::log::EventHandler {
        public:
            explicit ToWriteable(
                    satcat5::io::Writeable* dst,
                    satcat5::log::EventHandler* cc = 0);
            ~ToWriteable() SATCAT5_OPTIONAL_DTOR;
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;

        private:
            satcat5::io::Writeable* const m_dst;
            satcat5::log::EventHandler* const m_cc;
        };

        // Define basic priority codes.
        constexpr s8 DEBUG      = -20;
        constexpr s8 INFO       = -10;
        constexpr s8 WARNING    =   0;
        constexpr s8 ERROR      = +10;
        constexpr s8 CRITICAL   = +20;

        // Start the logging system and connect it to the designated output.
        // (Note: Calling log_start(0) stops the logging system.)
        void start(satcat5::log::EventHandler* dst);

        // Ephemeral Log class.
        class Log final {
        public:
            // Constructor sets priority and optionally the first string.
            explicit Log(s8 priority);
            Log(s8 priority, const char* str);
            Log(s8 priority, const char* str1, const char* str2);

            // Destructor sends the message.
            ~Log();

            // Formatting methods for various data types.
            // Returns reference to itself to make chaining easy.
            Log& write(const char* str);
            Log& write(u8 val);
            Log& write(u16 val);
            Log& write(u32 val);
            Log& write(u64 val);
            Log& write(const u8* val, unsigned nbytes);

        private:
            // Forbid use of copy constructor.
            Log(const Log&);                // Note: No implementation!
            Log& operator=(const Log&);     // Note: No implementation!

            // Internal formatting functions.
            void wr_str(const char* str);
            void wr_hex(u32 val, unsigned nhex);

            const s8 m_priority;
            unsigned m_wridx;
            char m_buff[SATCAT5_LOG_MAXLEN+1];
        };
    }
}

// Enable concise syntax?
// This requires adding a few objects to the top-level namespace.
#if SATCAT5_LOG_CONCISE
    using satcat5::log::Log;
    constexpr s8 LOG_DEBUG      = satcat5::log::DEBUG;
    constexpr s8 LOG_INFO       = satcat5::log::INFO;
    constexpr s8 LOG_WARNING    = satcat5::log::WARNING;
    constexpr s8 LOG_ERROR      = satcat5::log::ERROR;
    constexpr s8 LOG_CRITICAL   = satcat5::log::CRITICAL;
#endif
