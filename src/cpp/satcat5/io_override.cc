//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_override.h>

using satcat5::io::CopyMode;
using satcat5::io::Override;
using satcat5::io::Readable;
using satcat5::io::Writeable;

Override::Override(Writeable* dst, Readable* src, CopyMode mode)
    : ReadableRedirect(src)
    , WriteableRedirect(dst)
    , m_dev_rd(src)
    , m_ovr_rd(nullptr)
    , m_dev_wr(dst)
    , m_ovr_wr(nullptr)
    , m_mode(mode)
    , m_remote(false)
    , m_timeout(30000)
{
    if (m_dev_rd) m_dev_rd->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
Override::~Override() {
    if (m_dev_rd) m_dev_rd->set_callback(0);
    if (m_ovr_rd) m_ovr_rd->set_callback(0);
}
#endif

void Override::set_override(bool remote) {
    // Set new mode, then reconfigure timer if applicable.
    m_remote = remote;
    watchdog_reset();
}

void Override::set_remote(Writeable* tx, Readable* rx) {
    // Cleanup previous connection if applicable.
    if (m_ovr_rd) m_ovr_rd->set_callback(0);
    // Link to the new connection.
    m_ovr_rd = rx;
    m_ovr_wr = tx;
    if (m_ovr_rd) m_ovr_rd->set_callback(this);
    // If there's already data available, enter override mode.
    if (m_ovr_rd && m_ovr_rd->get_read_ready()) set_override(true);
}

void Override::set_timeout(unsigned msec) {
    // Set new timeout, then reset timer if applicable.
    m_timeout = msec;
    watchdog_reset();
}

void Override::data_rcvd(satcat5::io::Readable* src) {
    if (m_ovr_rd == src) {
        // New data from the remote controller.
        set_override(true);
        src->copy_and_finalize(m_dev_wr, m_mode);
    } else if (m_remote) {
        // New data from the I/O device (remote mode).
        src->copy_and_finalize(m_ovr_wr, m_mode);
    } else {
        // New data from the I/O device (local mode).
        read_notify();
    }
}

void Override::data_unlink(satcat5::io::Readable* src) {
    if (m_dev_rd == src) {m_dev_rd = 0; read_src(&null_read);}
    if (m_ovr_rd == src) {m_ovr_rd = 0;}
}

void Override::timer_event() {
    // Timeout elapsed, revert to local mode.
    set_override(false);
}

void Override::watchdog_reset() {
    if (m_remote && m_timeout) {
        timer_once(m_timeout);
    } else {
        timer_stop();
    }
}
