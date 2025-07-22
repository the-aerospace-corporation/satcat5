//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_broadcast.h>
#include <satcat5/utils.h>

using satcat5::io::WriteableBroadcast;
using satcat5::util::min_unsigned;


// Available write space is the minimum of all Writeables.
unsigned WriteableBroadcast::get_write_space() const {
    unsigned ws = UINT32_MAX; // Large default if no open Writeables.
    for (unsigned i = 0; i < m_size; ++i) {
        if (m_dsts[i]) { ws = min_unsigned(ws, m_dsts[i]->get_write_space()); }
    }
    return ws;
}

// Broadcast call.
void WriteableBroadcast::write_abort() {
    for (unsigned i = 0; i < m_size; ++i) {
        if (m_dsts[i]) { m_dsts[i]->write_abort(); }
    }
}

// Broadcast call.
void WriteableBroadcast::write_bytes(unsigned nbytes, const void* src) {
    if (nbytes <= get_write_space()) {
        for (unsigned i = 0; i < m_size; ++i) {
            if (m_dsts[i]) { m_dsts[i]->write_bytes(nbytes, src); }
        }
    } else {
        write_overflow();
    }
}

// Return OK only if all write_finalize() calls were successful.
bool WriteableBroadcast::write_finalize() {
    unsigned n_ok = 0;
    for (unsigned i = 0; i < m_size; ++i) {
        if (!m_dsts[i] || m_dsts[i]->write_finalize()) { ++n_ok; }
    }
    return (n_ok == m_size);
}

// Broadcast call.
void WriteableBroadcast::write_next(u8 data) {
    for (unsigned i = 0; i < m_size; ++i) {
        if (m_dsts[i]) { m_dsts[i]->write_next(data); }
    }
}

// Broadcast call.
void WriteableBroadcast::write_overflow() {
    for (unsigned i = 0; i < m_size; ++i) {
        if (m_dsts[i]) { m_dsts[i]->write_overflow(); }
    }
}
