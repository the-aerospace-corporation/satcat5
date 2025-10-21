//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_counter.h>
#include <satcat5/utils.h>

using satcat5::io::Counter;
using satcat5::io::CounterInline;
using satcat5::io::CounterSimple;
using satcat5::io::TrafficStats;

unsigned CounterSimple::byte_count(bool reset)
    { return satcat5::util::poll_counter(m_byte_ct, reset); }
unsigned CounterSimple::frame_count(bool reset)
    { return satcat5::util::poll_counter(m_frm_ct, reset); }
unsigned CounterSimple::error_count(bool reset)
    { return satcat5::util::poll_counter(m_err_ct, reset); }

void CounterInline::write_abort() {
    if (m_frm_len) ++m_err_ct;
    m_frm_len = 0;
    WriteableRedirect::write_abort();
}

void CounterInline::write_bytes(unsigned nbytes, const void* src) {
    m_frm_len += nbytes;
    WriteableRedirect::write_bytes(nbytes, src);
}

bool CounterInline::write_finalize() {
    unsigned len = m_frm_len;
    m_frm_len = 0;
    bool ok = WriteableRedirect::write_finalize();
    if (ok) {
        m_byte_ct += len;
        ++m_frm_ct;
    } else if (len) {
        ++m_err_ct;
    }
    return ok;
}

void CounterInline::write_next(u8 data) {
    ++m_frm_len;
    WriteableRedirect::write_next(data);
}

bool TrafficStats::any() const {
    return sent_bytes
        || sent_frames
        || rcvd_bytes
        || rcvd_frames
        || rcvd_errors;
}

TrafficStats TrafficStats::query(Counter& rx, Counter& tx) {
    return TrafficStats {
        tx.byte_count(),
        tx.frame_count(),
        rx.byte_count(),
        rx.frame_count(),
        rx.error_count(),
    };
}
