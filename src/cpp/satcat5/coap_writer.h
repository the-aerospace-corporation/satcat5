//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Message formatting for the Constrained Applications Protocol (CoAP)
//
// This file implements message formatting for the Constrained Applications
// Protocol (CoAP) defined in IETF RFC-7252:
//  https://www.rfc-editor.org/rfc/rfc7252
//
// The coap::Writer object is typically ephemeral:
//  * Create a coap::Writer object, attached to any Writeable sink.
//  * Call write_header(...) to write the CoAP header.
//  * Call write_option(...) for each desired option field.
//  * Call write_data(...) to write data and finalize the message.
//

#pragma once

#include <satcat5/coap_constants.h>
#include <satcat5/coap_reader.h>
#include <satcat5/io_writeable.h>

namespace satcat5 {
    namespace coap {
        class Writer final {
        public:
            // Create this object and set the destination.
            constexpr Writer(satcat5::io::Writeable* dst,
                bool write_max_age=true)
                : m_dst(dst), m_last_opt(0), m_insert_max_age(write_max_age) {}

            // Is this object ready for writing?
            // Note: This is the only safe method if m_dst is null.
            inline bool ready() const
                { return m_dst && m_dst->get_write_space(); }

            // Always start by writing the header, with optional token.
            // Token length can be set manually (tkl > 0) or automatically.
            bool write_header(u8 type, Code code, u16 msg_id,
                u64 token = 0, u8 tkl = 0);

            // A response variant of write_header that copies msg_id, token, and
            // token length from an incoming message
            inline bool write_header(u8 type, Code code, Reader& msg) {
                return write_header(type, code,
                    msg.msg_id(), msg.token(), msg.tkl());
            }

            // Write option(s) one at a time, in various formats.
            // Note: Options MUST be written in ascending-ID order.
            bool write_option(u16 id, unsigned len, const void* data);
            bool write_option(u16 id, const char* str);
            bool write_option(u16 id, u64 value);

            // After the last option, start writing message data.
            // Call this method exactly once, then finalize when ready.
            satcat5::io::Writeable* write_data();

            // After the last option, finish with an empty message.
            inline bool write_finalize()
                { insert_max_age(); return m_dst->write_finalize(); }

        protected:
            // Internal write methods.
            bool write_optid(u16 id, unsigned len);
            void write_varint(u64 x, unsigned len);
            void insert_max_age(u16 next_id = 0);

            satcat5::io::Writeable* const m_dst;
            u16 m_last_opt;                 // Previous option-ID
            bool m_insert_max_age;          // Add Max-Age=0 to disable caching
        };
    }
}
