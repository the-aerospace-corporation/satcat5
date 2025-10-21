//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_checksum.h>

using satcat5::io::ChecksumRxCommon;
using satcat5::io::ChecksumTxCommon;
using satcat5::io::TrafficStats;

void ChecksumTxCommon::write_overflow() {
    m_ovr = true;               // Flag persists until end-of-frame
}

void ChecksumTxCommon::write_abort() {
    if (m_frm_len) ++m_err_ct;  // Count this as an error?
    chk_reset();                // Reset internal state
    m_ovr = false;
    m_frm_len = 0;
    m_dst->write_abort();       // Forward error event
}

bool ChecksumTxCommon::chk_finalize() {
    bool ok = !m_ovr;           // Overflow error?
    if (ok) {
        m_byte_ct += m_frm_len;
        ++m_frm_ct;
    } else {
        m_dst->write_abort();
    }
    chk_reset();                // Reset internal state
    m_ovr = false;
    m_frm_len = 0;
    return ok;                  // Continue finalize event?
}

unsigned ChecksumRxCommon::get_write_space() const {
    return m_dst->get_write_space();
}

void ChecksumRxCommon::write_abort() {
    if (m_frm_len) ++m_err_ct;  // Count this as an error?
    chk_reset();                // Reset internal state
    m_frm_len = 0;
    m_dst->write_abort();       // Forward error event
}
