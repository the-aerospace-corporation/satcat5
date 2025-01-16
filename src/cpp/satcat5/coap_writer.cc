//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cstring>
#include <satcat5/coap_writer.h>
#include <satcat5/io_writeable.h>
#include <satcat5/utils.h>

using satcat5::coap::Code;
using satcat5::coap::Writer;
using satcat5::util::write_be_u64;

// Predict the required length for an integer field.
// (Clients SHOULD skip leading zeros to keep messages short.)
static unsigned varint_len(u64 x) {
    unsigned len = 0;
    while (x) {++len; x >>= 8;}
    return len;
}

bool Writer::write_header(u8 type, Code code, u16 msg_id, u64 token, u8 tkl) {
    // Automatically determine the required token length?
    if (token && !tkl) tkl = varint_len(token);

    // Disable auto-insert of Max-Age key for Empty packets
    if (code == CODE_EMPTY) { m_insert_max_age = false; }

    // Write the CoAP header (Section 3).
    m_dst->write_u8(VERSION1 | type | tkl);
    m_dst->write_u8(code.value);
    m_dst->write_u16(msg_id);
    if (tkl) write_varint(token, tkl);
    return true; // Success!
}

bool Writer::write_option(u16 id, unsigned len, const void* data) {
    insert_max_age(id); // Auto-Insert if necessary
    bool ok = write_optid(id, len);
    if (ok) m_dst->write_bytes(len, data);
    return ok;
}

bool Writer::write_option(u16 id, const char* str) {
    return write_option(id, strlen(str), str);
}

bool Writer::write_option(u16 id, u64 value) {
    insert_max_age(id); // Auto-Insert if necessary
    unsigned len = varint_len(value);
    bool ok = write_optid(id, len);
    if (ok) write_varint(value, len);
    return ok;
}

satcat5::io::Writeable* Writer::write_data() {
    insert_max_age(); // Insert Max-Age even if no options added
    m_dst->write_u8(PAYLOAD_MARKER);
    return m_dst;
}

bool Writer::write_optid(u16 id, unsigned len) {
    // Options must be written in ascending order.
    if (id < m_last_opt) return false;
    u16 delta = id - m_last_opt;
    m_last_opt = id;

    // Determine 4-bit "option delta" and "option length" codes.
    // (Both use the same structure for 0/1/2 extended bytes.)
    u8 pre_id, pre_len;
    if (delta < 13)         pre_id = u8(delta << 4);
    else if (delta < 269)   pre_id = 0xD0;
    else                    pre_id = 0xE0;
    if (len < 13)           pre_len = u8(len);
    else if (len < 269)     pre_len = 0x0D;
    else                    pre_len = 0x0E;

    // Write the combined variable-length tag (Section 3.1).
    m_dst->write_u8(pre_id | pre_len);
    if (pre_id == 0xD0) m_dst->write_u8(delta - 13);
    if (pre_id == 0xE0) m_dst->write_u16(delta - 269);
    if (pre_len == 0x0D) m_dst->write_u8(len - 13);
    if (pre_len == 0x0E) m_dst->write_u16(len - 269);
    return true; // Success!
}

void Writer::write_varint(u64 x, unsigned len) {
    // Convert to network order, then skip leading bytes.
    u8 tmp[8]; write_be_u64(tmp, x);
    unsigned skip = 8 - len;
    m_dst->write_bytes(len, tmp + skip);
}

void Writer::insert_max_age(u16 next_id) {
    // Auto-insert Max-Age=0 to explicitly disable caching (Section 5.6.1)
    if (!m_insert_max_age) { return; } // Not requested or already done
    if (next_id != 0 && next_id < OPTION_MAX_AGE) { return; } // Wait for ID
    if (next_id == OPTION_MAX_AGE) { // Max-Age overwritten
        m_insert_max_age = false; return;
    }
    write_optid(OPTION_MAX_AGE, 0); // 0-length is implicity =0
    m_insert_max_age = false; // Done
}
