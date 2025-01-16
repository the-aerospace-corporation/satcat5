//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/coap_reader.h>

using satcat5::coap::Option;
using satcat5::coap::Reader;
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

Reader::Reader(satcat5::io::Readable* src)
    : m_src(src)
    , m_state(State::OPTIONS)
    , m_error_code(CODE_EMPTY)
    , m_error_msg(nullptr)
    , m_type(src->read_u8())
    , m_code(src->read_u8())
    , m_id(src->read_u16())
    , m_token(0)
    , m_opt(src)
    , m_uri_path_wridx(0)
    , m_format()
    , m_size1()
{
    // Null-terminate the Uri-Path
    m_uri_path[0] = '\0';

    // Detect parsing errors in the initial header:
    if ((version() != satcat5::coap::VERSION1) || (tkl() > 8)) {
        m_state = State::ERROR;
        return;     // Illegal header parameters.
    } else if (m_code.is_empty()) {
        m_state = (tkl() || src->get_read_ready())
            ? State::ERROR : State::DATA;
        return;     // Empty message must really be empty.
    }

    // Read the token: 0-8 bytes with leading zeros.
    for (unsigned a = 0 ; a < tkl() ; ++a) {
        m_token = (m_token << 8) + src->read_u8();
    }
}

Reader::~Reader() {
    // Discard any remaining message data.
    m_src->read_finalize();
}

void Reader::read_options() {

    // Read all options
    while (m_state == State::OPTIONS) {

        // Consume any leftovers from the previous option.
        m_opt.read_finalize();

        // Are we ready to read the next option header?
        // (Next byte may be null if there is no message data.)
        if (!m_src->get_read_ready()) { m_state = State::DATA; return; }

        // Attempt to read the next option header and check for the data marker.
        u8 hdr = m_src->read_u8();
        if (hdr == satcat5::coap::PAYLOAD_MARKER) {
            m_state = State::DATA; return;
        }

        // Any other option: Parse the type and length fields.
        m_opt.m_id += read_var_int((hdr >> 4) & 0x0F);
        u16 len_tmp = read_var_int((hdr >> 0) & 0x0F);
        if (m_state == State::ERROR) { return; } // Type/length parsing error
        if (m_src->get_read_ready() < len_tmp) { // Confirm valid length
            m_state = State::ERROR; m_error_code = CODE_BAD_OPTION;
            m_error_msg = "Option length exceeded message bounds.";
            return;
        }
        m_opt.reset(len_tmp); // Reset LimitedRead to the length of this field

        // Handle a subset of known options. Others are passed to a separate
        // function to parse unknown options, which can be overloaded.
        switch (m_opt.id()) {
            case OPTION_URI_PATH: // Uri-Path
                append_uri_path(); // Parse Uri-Path string in separate function
                break;
            case OPTION_FORMAT: // Content-Format
                m_format = m_opt.value_uint();
                break;
            case OPTION_MAX_AGE: // Max-Age
                break; // Always ignore
            case OPTION_SIZE1: // Size1 (for block transfers)
                m_size1 = m_opt.value_uint();
                break;
            default: // Unrecognized, by default this rejects Critical IDs.
                read_user_option();
                break;
        }
    }
}

void Reader::read_user_option() {
    // Default implementation sets error if the ID is Critical
    if (m_opt.is_critical()) {
        m_state = State::ERROR; m_error_code = CODE_BAD_OPTION;
        m_error_msg = "Unrecognized Critical option ID";
    } // Ignore unrecognized Elective options
}

u16 Reader::read_var_int(u8 nybb) {
    // "Option Delta" and "Option Length" use the same format (Section 3.1).
    // We've been given the first nybble. Read up to two remaining bytes.
    if (nybb <= 12) return u16(nybb);
    if (nybb == 13) return u16(13u  + m_src->read_u8());
    if (nybb == 14) return u16(269u + m_src->read_u16());
    // Any other value is a message format error (required per Section 3.1).
    m_state = State::ERROR; m_error_code = CODE_BAD_OPTION;
    m_error_msg = "Option header contained an illegal value.";
    return 0;
}

void Reader::append_uri_path() {

    // Uri-Path sanity checks, +1 for '/'
    unsigned str_len = ((m_uri_path_wridx > 0) ? 1 : 0) + m_opt.len();
    if (m_uri_path_wridx + str_len > SATCAT5_COAP_MAX_URI_PATH_LEN) {
        m_state = State::ERROR; m_error_code = CODE_BAD_OPTION;
        m_error_msg = "Uri-Path exceeded maximum allowable length";
        return;
    }

    // Append to list with a '/' if necessary
    if (m_uri_path_wridx > 0) { m_uri_path[m_uri_path_wridx++] = '/'; }
    m_opt.value_str(m_uri_path + m_uri_path_wridx);
    m_uri_path_wridx += m_opt.len();
}

Readable* Reader::read_data() {
    // Sanity check: Options must have been parsed.
    if (m_state == State::OPTIONS) { read_options(); }
    return (m_state == State::DATA) ? m_src : nullptr;
}
