//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_piezo.h>

using satcat5::cfg::Piezo;

Piezo::Piezo(satcat5::cfg::ConfigBus* cfg, unsigned devaddr, unsigned regaddr)
    : m_reg(cfg->get_register(devaddr, regaddr))
    , m_queue(m_raw, sizeof(m_raw), 0)
{
    // Start from the idle / silent state.
    m_queue.set_callback(this);
    *m_reg = 0;
}

void Piezo::flush() {
    // Flush internal queue and return to idle/silent state.
    m_queue.clear();
    timer_stop();
    wait();
}

void Piezo::data_rcvd(satcat5::io::Readable* src) {
    // Unlink data_rcvd notifications while waiting for timer.
    m_queue.set_callback(0);
    // Execute the newly-received command.
    timer_event();
}

void Piezo::timer_event() {
    if (m_queue.get_read_ready() >= 6) {
        // Read and execute next command.
        timer_once(m_queue.read_u16());
        *m_reg = m_queue.read_u32();
    } else {
        // Idle/silent until we get more data.
        wait();
    }
}

void Piezo::wait() {
    // Silence output, then relink callback for data_rcvd notifications.
    *m_reg = 0;
    m_queue.set_callback(this);
}