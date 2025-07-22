//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/coap_reader.h>

using satcat5::coap::Option;
using satcat5::coap::Reader;
using satcat5::coap::ReadHeader;
using satcat5::coap::ReadSimple;
using satcat5::io::LimitedRead;
using satcat5::io::Readable;

unsigned Option::value_str(char* dst) {
    // Read raw bytes, then null-terminate.
    if (!read_bytes(m_len, dst)) return 0;
    dst[m_len] = 0;
    return m_len;
}

u64 Option::value_uint() {
    // Integers may be 0-8 bytes with leading zeros (Section 3.2).
    u64 accum = 0;
    for (unsigned a = 0 ; a < m_len ; ++a) {
        accum = (accum << 8) + read_u8();
    }
    return accum;
}

ReadHeader::ReadHeader(satcat5::io::Readable* src)
    : m_src(src)
    , m_state(State::OPTIONS)
    , m_error_code(CODE_EMPTY)
    , m_error_msg(nullptr)
    , m_type(src->read_u8())
    , m_code(src->read_u8())
    , m_id(src->read_u16())
    , m_token(0)
    , m_opt(src)
{
    if ((version() != satcat5::coap::VERSION1) || (tkl() > 8)) {
        // Detect illegal header parameters.
        set_error(CODE_BAD_REQUEST, "Bad header");
    } else if (m_code.is_empty()) {
        // Empty messages must really be empty.
        if (tkl() || src->get_read_ready())
            set_error(CODE_BAD_REQUEST, "Unexpected data");
        else
            m_state = State::DATA;
    } else {
        // Read the token: 0-8 bytes with leading zeros.
        for (unsigned a = 0 ; a < tkl() ; ++a) {
            m_token = (m_token << 8) + src->read_u8();
        }
    }
}

bool ReadHeader::next_option() {
    // Sanity check: Is the parser in the expected state?
    if (m_state != State::OPTIONS) return false;

    // Consume any leftovers from the previous option.
    m_opt.read_finalize();

    // If there is no message data, then end-of-frame marks the last option.
    if (!m_src->get_read_ready()) {
        m_state = State::DATA; return false;
    }

    // Otherwise, read the next byte and check for the data marker.
    u8 hdr = m_src->read_u8();
    if (hdr == satcat5::coap::PAYLOAD_MARKER) {
        m_state = State::DATA; return false;
    }

    // Parse the rest of the option header.
    m_opt.m_id += read_var_int((hdr >> 4) & 0x0F);
    u16 len_tmp = read_var_int((hdr >> 0) & 0x0F);
    if (m_state == State::ERROR || m_src->get_read_ready() < len_tmp) {
        set_error(CODE_BAD_OPTION, "Bad option length");
        return false;
    }

    // Reset m_opt's LimitedRead to the length of the field.
    m_opt.reset(len_tmp);
    return true;
}

Readable* ReadHeader::read_data() {
    // If we're still in the options state, skip ahead to message data.
    while (m_state == State::OPTIONS) next_option();
    return (m_state == State::DATA) ? m_src : nullptr;
}

u16 ReadHeader::read_var_int(u8 nybb) {
    // "Option Delta" and "Option Length" use the same format (Section 3.1).
    // We've been given the first nybble. Read up to two remaining bytes.
    if (nybb <= 12) return u16(nybb);
    if (nybb == 13) return u16(13u  + m_src->read_u8());
    if (nybb == 14) return u16(269u + m_src->read_u16());
    // Any other value is a message format error (required per Section 3.1).
    set_error(CODE_BAD_OPTION, "Bad option length");
    return 0;
}

Reader::Reader(satcat5::io::Readable* src)
    : ReadHeader(src)
    , m_uri_path{}
    , m_uri_path_wridx(0)
{
    // Null-terminate the Uri-Path
    m_uri_path[0] = '\0';
}

void Reader::read_options() {
    // Read each option...
    while (next_option()) {
        // Handle a subset of known options. Others are passed to a separate
        // function to parse unknown options, which can be overloaded.
        switch (m_opt.id()) {
            case OPTION_URI_PATH:   // Uri-Path
                append_uri_path();  // Parse Uri-Path string in separate function
                break;
            case OPTION_FORMAT:     // Content-Format
                m_format = m_opt.value_uint();
                break;
            case OPTION_MAX_AGE:    // Max-Age (ignored)
                break;
            case OPTION_BLOCK1:     // Block1 (RFC7959)
                m_block1 = m_opt.value_uint();
                break;
            case OPTION_BLOCK2:     // Block2 (RFC7959)
                m_block2 = m_opt.value_uint();
                break;
            case OPTION_SIZE1:      // Size1 (RFC7959)
                m_size1 = m_opt.value_uint();
                break;
            default:                // All other options...
                read_user_option(); // Call user-defined handler
                // Note: This cannot be moved into the Reader constructor due
                // to order-of-operations when creating the child object.
                break;
        }
    }
}

void Reader::append_uri_path() {
    // Uri-Path sanity checks, +1 for '/'
    unsigned str_len = ((m_uri_path_wridx > 0) ? 1 : 0) + m_opt.len();
    if (m_uri_path_wridx + str_len > SATCAT5_COAP_MAX_URI_PATH_LEN) {
        set_error(CODE_BAD_OPTION, "Uri-Path exceeded max length");
        return;
    }

    // Append to list with a '/' if necessary
    if (m_uri_path_wridx > 0) { m_uri_path[m_uri_path_wridx++] = '/'; }
    m_opt.value_str(m_uri_path + m_uri_path_wridx);
    m_uri_path_wridx += m_opt.len();
}

void ReadSimple::read_user_option() {
    // If we've reached this point, the option is unrecognized.
    // Handle Critical vs Elective options as required in RFC7252.
    if (m_opt.is_critical()) {
        set_error(CODE_BAD_OPTION, "Unrecognized Critical option");
    }
}
