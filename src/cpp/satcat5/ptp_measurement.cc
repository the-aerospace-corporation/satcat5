//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/ptp_client.h>
#include <satcat5/ptp_measurement.h>
#include <satcat5/utils.h>

using satcat5::ptp::Callback;
using satcat5::ptp::Header;
using satcat5::ptp::Measurement;
using satcat5::ptp::MeasurementCache;
using satcat5::ptp::PortId;
using satcat5::ptp::Source;
using satcat5::ptp::Time;
using satcat5::ptp::TIME_ZERO;
using satcat5::util::modulo_add_uns;

void Source::notify_callbacks(const satcat5::ptp::Measurement& meas)
{
    Callback* current = m_callbacks.head();
    while (current) {
        current->ptp_ready(meas);
        current = m_callbacks.next(current);
    }
}

Callback::Callback(satcat5::ptp::Client* client)
    : m_client(client), m_next(0)
{
    if (m_client) {
        m_client->add_callback(this);
    }
}

Callback::~Callback()
{
    if (m_client) {
        m_client->remove_callback(this);
    }
}

bool Measurement::done() const
{
    return (t1 != TIME_ZERO)
        && (t2 != TIME_ZERO)
        && (t3 != TIME_ZERO)
        && (t4 != TIME_ZERO);
}

void Measurement::log_to(satcat5::log::LogBuffer& wr) const {
    wr.wr_str("\n  t1");  t1.log_to(wr);
    wr.wr_str("\n  t2");  t2.log_to(wr);
    wr.wr_str("\n  t3");  t3.log_to(wr);
    wr.wr_str("\n  t4");  t4.log_to(wr);
}

bool Measurement::match(const Header& hdr, const PortId& port) const
{
    // Follow guidelines from Section 10.2.1 and Section 10.3.1.
    // (Caller provides either sourcePortIdentity or requestingPortIdentity.)
    return (ref.domain == hdr.domain)
        && (ref.sdo_id == hdr.sdo_id)
        && (ref.seq_id == hdr.seq_id)
        && (ref.src_port == port);
}

Time Measurement::mean_path_delay() const
{
    // See also: Section 11.3.1.
    return ((t2 - t1) + (t4 - t3)) / 2;
}

Time Measurement::mean_link_delay() const
{
    // See also: Section 11.4.2.
    return (t4 - t1) / 2;
}

Time Measurement::offset_from_master() const
{
    // See also: Section 11.2.
    return ((t2 - t1) + (t3 - t4)) / 2;
}

void Measurement::reset(const Header& hdr)
{
    ref = hdr;
    t1 = TIME_ZERO;
    t2 = TIME_ZERO;
    t3 = TIME_ZERO;
    t4 = TIME_ZERO;
}

Measurement* MeasurementCache::find(const Header& hdr, const PortId& port)
{
    // Cache size is small (2-8 typ), so direct linear search is fine.
    for (unsigned a = 0 ; a < SATCAT5_PTP_CACHE_SIZE ; ++a) {
        if (m_buff[a].match(hdr, port)) return m_buff + a;
    }
    return 0;   // No match
}

Measurement* MeasurementCache::push(const Header& hdr)
{
    Measurement* next = m_buff + m_next_wr;
    m_next_wr = modulo_add_uns(m_next_wr + 1, SATCAT5_PTP_CACHE_SIZE);
    next->reset(hdr);
    return next;
}
