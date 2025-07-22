//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Diagnostic logging to UART and/or Ethernet ports
//!
//!\details
//! `Log` objects are used for diagnostic logging, with a few simple
//! formatting options.  They are intended for simple debugging while
//! being much lighter-weight than printf() or sprintf().  Log messages
//! can be conveyed to a console, a UART, or even a network interface.
//! Each `Log` message carries a priority code to allow filtering.
//!
//! The objects in this file are used to generate log messages.  For
//! receiving messages, \see log_cbor.h or the "test/log_viewer" tool.
//!
//! Each `Log` object formats and emits a single human-readable message.
//! The `Log` object is ephemeral, with chaining for readable syntax.
//! Additional "write" calls append information to the message; the final
//! message is sent when the `Log` object falls out of scope.
//!
//! Each of the three examples below produces the same formatted message:
//!\code
//!      using satcat5::log::Log;
//!
//!      void example1(u8 errcode) {
//!          Log(satcat5::log::WARNING, "Oh noooo").write(errcode);
//!      }
//!
//!      void example2(u8 errcode) {
//!          Log(satcat5::log::WARNING).write("Oh noooo").write(errcode);
//!      }
//!
//!      void example3(u8 errcode) {
//!          Log log(satcat5::log::WARNING);
//!          log.write("Oh noooo");
//!          log.write(errcode);
//!      }
//!\endcode
//!
//! When the `Log` object falls out of scope, the message contents are written to
//! every object that defines the `log::EventHandler` interface.

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
        //! Defines the interface for accepting Log messages.
        //!
        //! \link log.h SatCat5 logging system concepts. \endlink
        //!
        //! To receive `Log` messages, derive a child class and override the
        //! `log_event` method.  The constructor automatically appends new
        //! `EventHandler` objects to a global list of Log recipients.
        class EventHandler {
        public:
            //! Callback for each formatted Log message.
            //! Child class must override this method.)
            virtual void log_event(s8 priority, unsigned nbytes, const char* msg) = 0;
        protected:
            //! Constructor automatically manages the list of active handler objects.
            EventHandler();
            ~EventHandler() SATCAT5_OPTIONAL_DTOR;
        private:
            friend satcat5::util::ListCore;
            satcat5::log::EventHandler* m_next;
        };

        //! Copy `Log` messages to any `Writeable` interface.
        //!
        //! \link log.h SatCat5 logging system concepts. \endlink
        //!
        //! This is the simplest logging `EventHandler`, often used with a
        //! designated debug UART to produce a stream of human-readable text.
        //!
        //! The output can be directed to any `Writeable` interface.
        class ToWriteable final : public satcat5::log::EventHandler {
        public:
            //! Bind this object to the designated output interface.
            explicit ToWriteable(satcat5::io::Writeable* dst);

            //! Implement the `EventHandler` API.
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;

        private:
            satcat5::io::Writeable* const m_dst;
        };

        //! Define basic priority codes for log messages.
        //! Larger numeric codes indicate greater message priority.
        //!@{
        constexpr s8 DEBUG      = -20;
        constexpr s8 INFO       = -10;
        constexpr s8 WARNING    =   0;
        constexpr s8 ERROR      = +10;
        constexpr s8 CRITICAL   = +20;
        //!@}

        //! Convert priority code to a human-readable UTF-8 string.
        //! By default, the priority code is a UTF-8 emoji. For example,
        //! `WARNING` gets the "caution" sign and `CRITICAL` gets a skull
        //! and crossbones. To replace this with a fixed-width plaintext
        //! code, set SATCAT5_LOG_EMOJI = 0.
        const char* priority_label(s8 priority);

        //! Internal buffer used by the `Log` class.
        //!
        //! \link log.h SatCat5 logging system concepts. \endlink
        //!
        //! This buffer holds the contents of a `Log` message, provides
        //! low-level formatting, and provides length checks to ensure
        //! that long messages are truncated safely.
        //!
        //! The `LogBuffer` class is the required API for classes
        //! that wish to provide custom output formatting.
        //! \see satcat5::log::Log::write_obj
        class LogBuffer final {
        public:
            //! Constructor for an empty buffer.
            LogBuffer() : m_wridx(0) {}

            //! Buffer contents, in the form of a null-terminated string.
            const char* c_str();

            //! Write a fixed-length UTF-8 string.
            void wr_fix(const char* str, unsigned len);
            //! Write a null-terminated UTF-8 string.
            void wr_str(const char* str);
            //! Write an integer (u32) in hexadecimal format.
            //! The second argument is the number of hexadecimal digits.
            void wr_h32(u32 val, unsigned nhex = 8);
            //! Write an integer (u64) in hexadecimal format.
            //! The second argument is the number of hexadecimal digits.
            void wr_h64(u64 val, unsigned nhex = 16);
            //! Write an unsigned integer (u32) in decimal format.
            //! For zero-padding to N digits, set second argument to 10^N-1.
            //! e.g., wr_d32(123, 9999) --> "0123"
            void wr_d32(u32 val, unsigned zpad = 0);
            //! Write an unsigned integer (u64) in decimal format.
            //! For zero-padding to N digits, set second argument to 10^N-1.
            void wr_d64(u64 val, unsigned zpad = 0);
            //! Write a signed integer (s32) in decimal format.
            //! For zero-padding to N digits, set second argument to 10^N-1.
            void wr_s32(s32 val, unsigned zpad = 0);
            //! Write a signed integer (s64) in decimal format.
            //! For zero-padding to N digits, set second argument to 10^N-1.
            void wr_s64(s64 val, unsigned zpad = 0);
            //! Legacy alias for `wr_d32`.
            inline void wr_dec(u32 val) {wr_d32(val);}
            //! Legacy alias for `wr_h32`.
            inline void wr_hex(u32 val) {wr_h32(val);}

            //! Number of characters written to this buffer.
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

        //! The `Log` class creates and formats one log message.
        //!
        //! \link log.h SatCat5 logging system concepts. \endlink
        //!
        //! Each `Log` is an emphemeral object that creates, formats, and
        //! emits a human-readable message.  When the `Log` object falls
        //! out of scope, the message is sent to each `EventHandler`.
        class Log final {
        public:
            //! Constructor sets priority and optionally the first string.
            //!@{
            explicit Log(s8 priority);
            Log(s8 priority, const char* str);
            Log(s8 priority, const char* str1, const char* str2);
            Log(s8 priority, const void* str, unsigned nbytes);
            //!@}

            //! Destructor sends the message.
            ~Log();

            //! Formatting methods for various data types.
            //! Each "write" method appends text to the `Log` message.
            //! By convention, integer types add prefix " = 0x" and print
            //! as a fixed-width hexadecimal value. Use "write10" for decimal.
            //! Other values, except strings, add prefix " = " instead.
            //! Network types use conventional form (e.g., "192.168.1.42").
            //! Returns reference to itself to make chaining easy.
            //!@{
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
            //!@}

            //! Print integer as a decimal value with no leading zeros.
            //! As with "write", these methods append text to the output
            //! and include the " = " prefix. Signed values also include
            //! a leading "+" or "-" token.
            //!@{
            Log& write10(s32 val);  // Signed (e.g., "+1234" or "-1234")
            Log& write10(s64 val);
            Log& write10(u32 val);  // Unsigned (e.g., "1234")
            Log& write10(u64 val);
            inline Log& write10(s8  val)    {return write10(s32(val));}
            inline Log& write10(s16 val)    {return write10(s32(val));}
            inline Log& write10(u8  val)    {return write10(u32(val));}
            inline Log& write10(u16 val)    {return write10(u32(val));}
            //!@}

            //! Templated wrapper for custom output formatting.
            //! To implement custom formatting for a given object, that
            //! object must impelment the following method:
            //!\code
            //!     void log_to(satcat5::log::LogBuffer& wr) const;
            //!\endcode
            //! The log_to() method should then write to the provided
            //! `LogBuffer` object using its formatting methods.
            template <class T> inline Log& write_obj(const T& obj)
                {obj.log_to(m_buff); return *this;}

        private:
            // Forbid use of copy constructor.
            Log(const Log&) = delete;
            Log& operator=(const Log&) = delete;

            const s8 m_priority;
            satcat5::log::LogBuffer m_buff;
        };

        //! Hard-reset of global variables at the start of each unit test.
        //! (Unit test only, not recommended for use in production software.)
        //! This may leak memory but prevents cross-test contamination.
        //! Returns true if globals were already in the expected state.
        bool pre_test_reset();
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
