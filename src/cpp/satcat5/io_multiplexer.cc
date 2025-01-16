//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_multiplexer.h>

using satcat5::io::EventListener;
using satcat5::io::MuxDown;
using satcat5::io::MuxPort;
using satcat5::io::MuxUp;
using satcat5::io::Readable;
using satcat5::io::Writeable;

MuxDown::MuxDown(unsigned size, MuxPort* ports, Readable* src, Writeable* dst)
    : m_size(size), m_index(-1), m_ports(ports), m_src(src), m_dst(dst)
{
    m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
MuxDown::~MuxDown() {
    // Unlink callback if applicable.
    if (m_src) m_src->set_callback(0);
}
#endif

void MuxDown::select(unsigned idx) {
    // Note the active port index.
    m_index = idx;

    // Link selected virtual port to the shared port, others to a placeholder.
    for (unsigned a = 0 ; a < m_size ; ++a) {
        Readable*  src = (a == idx) ? m_src : 0;
        Writeable* dst = (a == idx) ? m_dst : &null_write;
        m_ports[a].attach(src, dst);
    }
}

void MuxDown::data_rcvd(satcat5::io::Readable* src) {
    // Forward events to the active controller, if any.
    if (m_index < m_size) m_ports[m_index].read_notify();
}

void MuxDown::data_unlink(satcat5::io::Readable* src) {m_src = 0;} // GCOVR_EXCL_LINE

#if SATCAT5_ALLOW_DELETION
MuxUp::~MuxUp() {
    // Cleanup all associated callback pointers.
    for (unsigned a = 0 ; a < m_size ; ++a) {
        if (m_src[a]) m_src[a]->set_callback(0);
    }
}
#endif

void MuxUp::port_set(unsigned idx, Readable* src, Writeable* dst) {
    // Register ourselves as the callback for all new ports.
    if (idx < m_size) {
        m_src[idx] = src;
        m_dst[idx] = dst;
        if (src) src->set_callback(this);
    }
}

void MuxUp::select(unsigned idx) {
    // Note the active port index.
    m_index = idx;

    // Redirect the upstream controller to the designated port.
    Readable*  src = (idx < m_size) ? m_src[idx] : 0;
    Writeable* dst = (idx < m_size) ? m_dst[idx] : &null_write;
    attach(src, dst);
}

void MuxUp::data_rcvd(satcat5::io::Readable* src) {
    Readable* ref = (m_index < m_size) ? m_src[m_index] : 0;
    if (src == ref) {
        // Forward events from the active source to the upstream callback.
        read_notify();
    } else {
        // Data from all other sources is immediately discarded.
        src->read_consume(src->get_read_ready());
        src->read_finalize();
    }
}

void MuxUp::data_unlink(satcat5::io::Readable* src) {
    // Cleanup any matching source pointers.
    for (unsigned a = 0 ; a < m_size ; ++a) {
        if (m_src[a] == src) m_src[a] = 0;
    }
}
