//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ptp_measurement.h>
#include <satcat5/ptp_source.h>

using satcat5::ptp::Callback;
using satcat5::ptp::Measurement;
using satcat5::ptp::Source;

void Source::notify_callbacks(const Measurement& meas) {
    Callback* current = m_callbacks.head();
    while (current) {
        current->ptp_ready(meas);
        current = m_callbacks.next(current);
    }
}

Callback::Callback(Source* source)
    : m_source(source), m_next(0)
{
    if (m_source) {
        m_source->add_callback(this);
    }
}

Callback::~Callback() {
    if (m_source) {
        m_source->remove_callback(this);
    }
}
