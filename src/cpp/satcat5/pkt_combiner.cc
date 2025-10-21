//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/pkt_combiner.h>

using satcat5::io::PacketCombiner;

PacketCombiner::PacketCombiner(satcat5::io::Writeable* dst,
                               u8* buff, unsigned buffbytes)
    : WriteableRedirect(&m_buff)
    , m_dst(dst)
    , m_buff(buff, buffbytes, 0)
    , m_timeout(0)
{
    m_buff.set_callback(this);
}

void PacketCombiner::send_now() {
    m_dst->write_finalize();

    // Reset timer
    if (m_timeout) {
        timer_stop();
        timer_once(m_timeout);
    }
}

void PacketCombiner::set_timeout(unsigned msec) {
    m_timeout = msec;
    if (m_timeout) {
        timer_once(m_timeout);
    } else {
        timer_stop();
    }
}

void PacketCombiner::data_rcvd(satcat5::io::Readable* src) {
    // Copy as many bytes as possible to the buffer
    bool done = false;
    while (!done) {
        src->copy_to(m_dst);

        // If buffer is full, send to dst and set done flag
        if (m_dst->get_write_space() == 0) {
            send_now();
            done = true;
        }

        // If end of frame, check for another, else set done flag
        if (src->get_read_ready() == 0) {
            src->read_finalize();
            if (!done && src->get_read_ready() == 0) { done = true; }
        }
    }
}

void PacketCombiner::timer_event() {
    send_now();
}
