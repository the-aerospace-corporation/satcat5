//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Message parsing for the Constrained Applications Protocol (CoAP)
//!
//!\details
//! This file implements message parsing for the Constrained Applications
//! Protocol (CoAP) defined in IETF RFC-7252:
//!  https://www.rfc-editor.org/rfc/rfc7252
//!
//! The coap::Reader object is typically ephemeral:
//!  * Create a coap::Reader object, attaching to any Readable source.
//!  * Constructor automatically reads basic header information.
//!  * User should call read_read() to access the message contents.
//!  * Destroy the coap::Reader object to finalize the parsing process.
//!
//! Any of these actions, including object creation, may trigger an error. The
//! error state can be checked via the `error()` function. If errored,
//! `error_code()` MUST return a the correct response code for the error, or
//! CODE_EMPTY if a Reset is required, and `error_msg()` MAY contain a diagnostic
//! payload.
//!
//! Options are parsed by the `coap::Reader::read_options()` method. Children of
//! coap::Reader MUST call this method in their constructor. The coap::Reader
//! class handles several CoAP options itself; other options of interest MAY be
//! supported in child classes by overriding the `read_user_option()` method.
//! If adding vendor-specific options, the chosen Option Number(s) MUST be in
//! the range [2048, 65000) per RFC7252 §12.2.

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
        //! Accessor for a single CoAP option field.
        //! \see coap_reader.h, coap::Reader, coap::Writer.
        class Option final : public satcat5::io::LimitedRead {
        public:
            //! Option Number (RFC-7252, Section 3.1).
            u16 id() const     { return m_id; }
            //! Option Number (RFC-7252, Section 3.1).
            u16 len() const    { return m_len; }

            //! Access the Option Value as a UTF-8 string ("string").
            //! To access raw bytes, use the LimitedRead API.
            unsigned value_str(char* dst);
            //! Access the Option Value as an unsigned integer ("uint").
            u64 value_uint();

            //! Option bit mapping indicates relevant properties (Section 5.4.6).
            //!@{
            bool is_critical() const    { return m_id & 0x0001; }
            bool is_unsafe() const      { return m_id & 0x0002; }
            bool no_cache_key() const   { return (m_id & 0x001E) == 0x001C; }
            //!@}

        private:
            // These methods should only be accessed by coap::ReadHeader.
            friend satcat5::coap::ReadHeader;
            constexpr explicit Option(satcat5::io::Readable* src)
                : LimitedRead(src, 0), m_id(0), m_len(0) {}
            inline Option* reset(unsigned len)
                { m_len = len; read_reset(len); return this; }
            u16 m_id, m_len;
        };

        //! Parser for CoAP message headers only.
        //! \see coap_reader.h, coap::Option.
        class ReadHeader {
        public:
            //! Create this object and read the message header only.
            explicit ReadHeader(satcat5::io::Readable* src);

            // Forbid unsafe assignment and copy operators.
            ReadHeader(const ReadHeader&) = delete;
            ReadHeader& operator=(const ReadHeader&) = delete;

            //! Consume current option and advance to the next one.
            //! \returns True until all options have been read.
            bool next_option();

            //! Access the message payload.
            //! Calling this method discards any unparsed options.
            satcat5::io::Readable* read_data();

            //! Forward read_finalize() to the inner source.
            inline void read_finalize()
                { m_src->read_finalize(); }

            // Accessors for the message header and parsing state.
            inline bool error() const               //!< Error during parsing?
                { return m_state == State::ERROR; }
            inline Code error_code() const          //!< Code for the error
                { return m_error_code; }
            inline const char* error_msg() const    //!< Optional message
                { return m_error_msg; }
            inline u8 version() const               //!< Version (Ver)
                { return m_type & 0xC0; }
            inline u8 type() const                  //!< Type (T)
                { return m_type & 0x30; }
            inline u8 tkl() const                   //!< Token length (TKL)
                { return m_type & 0x0F; }
            inline Code code() const                //!< Response code (CODE)
                { return m_code; }
            inline u16 msg_id() const               //!< Message ID
                { return m_id; }
            inline u64 token() const                //!< Token value
                { return m_token; }
            inline bool is_request() const          //!< CON or NON request?
                { return type() == TYPE_CON || type() == TYPE_NON; }
            inline bool is_response() const         //!< ACK request?
                { return type() == TYPE_ACK; }
            inline satcat5::coap::Option& option()  //!< Current option.
                { return m_opt;}

        protected:
            //! List of possible parser states.
            enum class State {OPTIONS, DATA, ERROR};

            //! Read variable-length integer from Option header.
            u16 read_var_int(u8 nybb);

            //! Set error code and stop further parsing.
            inline void set_error(Code code, const char* msg = "")
                { m_state = State::ERROR; m_error_code = code; m_error_msg = msg; }

            //! Source buffer of CoAP message
            satcat5::io::Readable* const m_src;

            // Reader state and error information if triggered.
            State m_state;                  //!< Parser state
            Code m_error_code;              //!< Error code, or Empty to Reset
            const char* m_error_msg;        //!< Diagnostic Payload for error

            // Header fields
            const u8 m_type;                //!< Version, type, TKL
            satcat5::coap::Code m_code;     //!< Status code x.yy
            const u16 m_id;                 //!< Message ID
            u64 m_token;                    //!< Token (0-8 bytes)

            //! Contents of the current option.
            satcat5::coap::Option m_opt;
        };

        //! Base-class for parsing CoAP message headers and options.
        //! \see coap_reader.h, coap::Option, coap::ReadSimple.
        //! This parser reads and stores the most common options, such as
        //! Uri-Path, Content-Format, and Size1. To process more options,
        //! create a child object that overrides `read_user_option`.
        //! To process only the basic CoAP options, use coap::ReadSimple.
        class Reader : public satcat5::coap::ReadHeader {
        public:
            //! Create this object and read the message header.
            //! The child class MUST call read_options in its constructor.
            explicit Reader(satcat5::io::Readable* src);

            // Forbid unsafe assignment and copy operators.
            Reader(const Reader&) = delete;
            Reader& operator=(const Reader&) = delete;

            //! Accessors for parsed options.
            //!@{
            inline satcat5::util::optional<const char*> uri_path() const // Uri-Path
                { return m_uri_path_wridx == 0 ?
                    satcat5::util::optional<const char*>() : m_uri_path; }
            inline satcat5::util::optional<u16> format() const  // Content-Format
                { return m_format; }
            inline satcat5::util::optional<u64> size1() const   // Size1
                { return m_size1; }
            inline satcat5::util::optional<u64> block() const   // Block1 & Block2 combined
                { return m_block1 ? m_block1 : m_block2; }      // TODO: Deprecate these?
            inline u16 block_size() const
                { return m_block1 ? block1_size() : block2_size(); }
            inline bool block_more() const
                { return m_block1 ? block1_more() : block2_more(); }
            inline u32 block_num() const
                { return m_block1 ? block1_num() : block2_num(); }
            inline satcat5::util::optional<u64> block1() const  // Block1 only
                { return m_block1; }
            inline u16 block1_size() const
                { return 1 << ((m_block1.value() & 0x7) + 4); }
            inline bool block1_more() const
                { return (m_block1.value() & 0x8) >> 3; }
            inline u32 block1_num() const
                { return (m_block1.value() & 0xFFFFFFF0) >> 4; }
            inline satcat5::util::optional<u64> block2()        // Block2 only
                { return m_block2; }
            inline u16 block2_size() const
                { return 1 << ((m_block2.value() & 0x7) + 4); }
            inline bool block2_more() const
                { return (m_block2.value() & 0x8) >> 3; }
            inline u32 block2_num() const
                { return (m_block2.value() & 0xFFFFFFF0) >> 4; }
            //!@}

        protected:
            //! Uri-Path string builder
            void append_uri_path();

            //! Read all option headers, storing supported option fields.
            //! For each unrecognized option, call `read_user_option`.
            //! The child class MUST call read_options in its constructor.
            void read_options();

            //! Handler called for each option with an unknown ID.
            //! When this method is called, use member variable `m_opt` to
            //! access the option ID and contents. \see coap::Option.
            //! The child class MUST define this method.
            virtual void read_user_option() = 0;

            //! URI path for this request.
            char m_uri_path[SATCAT5_COAP_MAX_URI_PATH_LEN + 1];
            unsigned m_uri_path_wridx;              //!< Index into `m_uri_path`
            satcat5::util::optional<u16> m_format;  //!< Content-Format
            satcat5::util::optional<u64> m_block1;  //!< Block1
            satcat5::util::optional<u64> m_block2;  //!< Block2
            satcat5::util::optional<u64> m_size1;   //!< Size1
        };

        //! Wrapper for coap::ReadOptions that automatically parses options,
        //! rejecting any message with unrecognized Critical options.
        //! \see coap_reader.h, coap::Option, coap::ReadOptions.
        class ReadSimple final : public satcat5::coap::Reader {
        public:
            //! Wrapper object automatically reads header and options.
            explicit ReadSimple(satcat5::io::Readable* src)
                : Reader(src) { read_options(); }

        protected:
            //! The default implementation simply rejects any unsupported
            //! "Critical" Option as defined in RFC 7252, Section 5.4.1.
            void read_user_option() override;
        };
    }
}
