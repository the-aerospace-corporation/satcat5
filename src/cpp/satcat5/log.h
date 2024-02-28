//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
// When the Log object falls out of scope, the message contents are written to
// every object that defines the "EventHandler" interface.  (The constructor
// for that class automatically adds itself to a global list.)
//

#pragma once

#include <satcat5/list.h>
#include <satcat5/types.h>

// Default parameters:
#ifndef SATCAT5_LOG_MAXLEN      // Maximum string length per message
#define SATCAT5_LOG_MAXLEN  255
#endif

#ifndef SATCAT5_LOG_CONCISE     // Enable concise syntax?
#define SATCAT5_LOG_CONCISE 1
#endif

#ifndef SATCAT5_WELCOME_EMOJI   // UTF-8 string: [satellite] [smiling cat] [five o'clock]
#define SATCAT5_WELCOME_EMOJI "\xf0\x9f\x9b\xb0\xef\xb8\x8f\xf0\x9f\x90\xb1\xf0\x9f\x95\x94"
#endif

namespace satcat5 {
    namespace log {
        // Define the interface for accepting Log messages.
        class EventHandler {
        public:
            // (Child class must override this method.)
            virtual void log_event(s8 priority, unsigned nbytes, const char* msg) = 0;
        protected:
            // Constructor automatically manage the list of active handler objects.
            EventHandler();
            ~EventHandler() SATCAT5_OPTIONAL_DTOR;
        private:
            friend satcat5::util::ListCore;
            satcat5::log::EventHandler* m_next;
        };

        // Basic LogEventHandler that copies contents to a UART or similar.
        // (And optionally carbon-copies the data to a second handler.)
        class ToWriteable final : public satcat5::log::EventHandler {
        public:
            explicit ToWriteable(satcat5::io::Writeable* dst);
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;

        private:
            satcat5::io::Writeable* const m_dst;
        };

        // Define basic priority codes.
        constexpr s8 DEBUG      = -20;
        constexpr s8 INFO       = -10;
        constexpr s8 WARNING    =   0;
        constexpr s8 ERROR      = +10;
        constexpr s8 CRITICAL   = +20;

        // Convert priority code to a human-readable UTF-8 string.
        // (May include emoji or plaintext labels, depending on build flags.)
        const char* priority_label(s8 priority);

        // Internal buffer used by the Log class, and by classes with
        // custom formatting methods. See also: Log::write_obj(...)
        class LogBuffer final {
        public:
            // Constructor for an empty buffer.
            LogBuffer() : m_wridx(0) {}

            // Write formatted elements to the internal buffer.
            void wr_fix(const char* str, unsigned len);     // Fixed-len string
            void wr_str(const char* str);                   // Null-term string
            void wr_hex(u32 val, unsigned nhex);            // Hexadecimal int
            void wr_dec(u32 val);                           // Decimal int
            void wr_d64(u64 val);                           // Decimal int

            // Current string length.
            unsigned len() const {return m_wridx;}

        private:
            friend satcat5::log::Log;

            // Forbid use of copy constructor.
            LogBuffer(const LogBuffer&) = delete;
            LogBuffer& operator=(const LogBuffer&) = delete;

            // Null-terminate the working buffer.
            inline void terminate() {m_buff[m_wridx] = 0;}

            // Internal buffer.
            unsigned m_wridx;
            char m_buff[SATCAT5_LOG_MAXLEN+1];
        };

        // Ephemeral Log class.
        class Log final {
        public:
            // Constructor sets priority and optionally the first string.
            explicit Log(s8 priority);
            Log(s8 priority, const char* str);
            Log(s8 priority, const char* str1, const char* str2);
            Log(s8 priority, const void* str, unsigned nbytes);

            // Destructor sends the message.
            ~Log();

            // Formatting methods for various data types.
            // All integer types print as fixed-width hexadecimal values.
            // Network types use conventional form (e.g., "192.168.1.42").
            // Returns reference to itself to make chaining easy.
            Log& write(const char* str);
            Log& write(bool val);
            Log& write(u8 val);
            Log& write(u16 val);
            Log& write(u32 val);
            Log& write(u64 val);
            Log& write(satcat5::io::Readable* rd);
            Log& write(const u8* val, unsigned nbytes);
            Log& write(const satcat5::eth::MacAddr& mac);
            Log& write(const satcat5::ip::Addr& ip);

            // Print integer as a decimal value with no leading zeros.
            Log& write10(s32 val);  // Signed (e.g., "+1234" or "-1234")
            Log& write10(s64 val);
            Log& write10(u32 val);  // Unsigned (e.g., "1234")
            Log& write10(u64 val);

            // Templated wrapper for any object with the following method:
            //  void log_to(satcat5::log::LogBuffer& wr) const;
            template <class T> inline Log& write_obj(const T& obj)
                {obj.log_to(m_buff); return *this;}

        private:
            // Forbid use of copy constructor.
            Log(const Log&) = delete;
            Log& operator=(const Log&) = delete;

            const s8 m_priority;
            satcat5::log::LogBuffer m_buff;
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
