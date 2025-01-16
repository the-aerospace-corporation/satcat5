//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Message parsing for the Constrained Applications Protocol (CoAP)
//
// This file implements message parsing for the Constrained Applications
// Protocol (CoAP) defined in IETF RFC-7252:
//  https://www.rfc-editor.org/rfc/rfc7252
//
// The coap::Reader object is typically ephemeral:
//  * Create a coap::Reader object, attaching to any Readable source.
//  * Constructor automatically reads basic header information.
//  * User should call read_options() once before reading any CoAP options.
//  * User should call read_read() to access the message contents.
//  * Destroy the coap::Reader object to finalize the parsing process.
//
// Any of these actions, including object creation, may trigger an error. The
// error state can be checked via the `error()` function. If errored,
// `error_code()` MUST return a the correct response code for the error, or
// CODE_EMPTY if a Reset is required, and `error_msg()` MAY contain a diagnostic
// payload.
//
// Options are parsed during the call to `read_options()`. Parsers for the set
// core CoAP options in the range [0, 256) SHOULD be included in the Reader
// class. Other options MAY be supported by Child classes by overriding the
// `read_user_option()` function. If adding vendor-specific options, the chosen
// Option Number(s) MUST be in the range [2048, 65000) per RFC7252 §12.2.
//

#pragma once

#include <satcat5/coap_constants.h>
#include <satcat5/io_readable.h>
#include <satcat5/utils.h>

// Maximum length of an assembled Uri-Path string, ignoring other Uri- options
// and an implicit leading /. Example: 'resource1/resource2/res3'
#ifndef SATCAT5_COAP_MAX_URI_PATH_LEN
#define SATCAT5_COAP_MAX_URI_PATH_LEN 64
#endif

namespace satcat5 {
    namespace coap {
        // Accessor for a single CoAP option field.
        class Option final : public satcat5::io::LimitedRead {
        public:
            // Access the Option Number and Option Length (Section 3.1)
            u16 id() const     { return m_id; }
            u16 len() const    { return m_len; }

            // Additional accessors for the Option Value.
            // (Or use the LimitedRead API to access the raw data.)
            unsigned value_str(char* dst);      // UTF-8 string ("string")
            u64 value_uint();                   // Unsigned integer ("uint")

            // Option bit mapping indicates relevant properties (Section 5.4.6)
            bool is_critical() const    { return m_id & 0x0001; }
            bool is_unsafe() const      { return m_id & 0x0002; }
            bool no_cache_key() const   { return (m_id & 0x001E) == 0x001C; }

        private:
            // These methods should only be accessed by coap::Reader.
            friend satcat5::coap::Reader;
            constexpr explicit Option(satcat5::io::Readable* src)
                : LimitedRead(src, 0), m_id(0), m_len(0) {}
            inline Option* reset(unsigned len)
                { m_len = len; read_reset(len); return this; }
            u16 m_id, m_len;
        };

        // Parser for CoAP message headers.
        class Reader {
        public:
            // Create this object and read the message header.
            explicit Reader(satcat5::io::Readable* src);
            ~Reader();

            // Accessors for the message header and parsing state.
            inline bool error() const       // Error during parsing?
                { return m_state == State::ERROR; }
            inline Code error_code() const  // Code for the error
                { return m_error_code; }
            inline const char* error_msg() const // Optional message
                { return m_error_msg; }
            inline u8 version() const       // Version (Ver)
                { return m_type & 0xC0; }
            inline u8 type() const          // Type (T)
                { return m_type & 0x30; }
            inline u8 tkl() const           // Token length (TKL)
                { return m_type & 0x0F; }
            inline Code code() const        // Response code (CODE)
                { return m_code; }
            inline u16 msg_id() const       // Message ID
                { return m_id; }
            inline u64 token() const        // Token value
                { return m_token; }
            inline bool is_request() const
                { return type() == TYPE_CON || type() == TYPE_NON; }
            inline bool is_response() const
                { return type() == TYPE_ACK; }

            // Accessors for parsed options, runs parsing if not yet complete.
            inline satcat5::util::optional<const char*> uri_path() { // Uri-Path
                if (m_state == State::OPTIONS) { read_options(); }
                return m_uri_path_wridx == 0 ?
                    satcat5::util::optional<const char*>() : m_uri_path; }
            inline satcat5::util::optional<u16> format() {     // Content-Format
                if (m_state == State::OPTIONS) { read_options(); }
                return m_format; }
            inline satcat5::util::optional<u64> size1() {      // Size1
                if (m_state == State::OPTIONS) { read_options(); }
                return m_size1; }

            // Read and parse all CoAP options.
            void read_options();

            // Returns the message payload, parsing options first if that has
            // not been completed.
            // Inherit from Readable?
            satcat5::io::Readable* read_data();

        protected:
            // List of possible parser states.
            enum class State {OPTIONS, DATA, ERROR};

            // Handler called when an option with an unknown ID is read. `m_opt`
            // will be the parsed option with the unknown ID when this function
            // is called. The default implementation simply rejects any Option
            // Number indicating a Critical option.
            // Child classes MAY overload this function to implement handlers
            // for extra options.
            virtual void read_user_option();

            // Read variable-length integer from Option header.
            u16 read_var_int(u8 nybb);          // Option header int

            // Uri-Path string builder
            void append_uri_path();

            // Source buffer of CoAP message
            satcat5::io::Readable* const m_src;

            // Reader state and error information if triggered.
            State m_state;                  // Parser state
            Code m_error_code;              // Error code, or Empty to Reset
            const char* m_error_msg;        // Diagnostic Payload for error

            // Header fields
            const u8 m_type;                // Version, type, TKL
            satcat5::coap::Code m_code;     // Status code x.yy
            const u16 m_id;                 // Message ID
            u64 m_token;                    // Token (0-8 bytes)

            // Options
            satcat5::coap::Option m_opt;    // Option contents
            char m_uri_path[SATCAT5_COAP_MAX_URI_PATH_LEN + 1]; // Uri-Path
            unsigned m_uri_path_wridx;      // Index into above
            satcat5::util::optional<u16> m_format; // Content-Format
            satcat5::util::optional<u64> m_size1;  // Size1
        };
    }
}
