//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/net_telemetry.h>
#include <satcat5/utils.h>

// Start of conditional compilation...
#if SATCAT5_CBOR_ENABLE

#include <qcbor/qcbor.h>

using satcat5::net::TelemetryCbor;
using satcat5::net::TelemetrySink;
using satcat5::net::TelemetrySource;
using satcat5::net::TelemetryTier;
using satcat5::net::TelemetryAggregator;
using satcat5::util::min_unsigned;


// Thin wrappers for the Ethernet and UDP constructors.
satcat5::eth::Telemetry::Telemetry(
        satcat5::eth::Dispatch* eth,
        const satcat5::eth::MacType& typ,
        bool concat_tiers)
    : satcat5::eth::AddressContainer(eth)
    , satcat5::net::TelemetryAggregator(concat_tiers)
    , satcat5::net::TelemetrySink(this)
{
    connect(satcat5::eth::MACADDR_BROADCAST, typ);
}

satcat5::udp::Telemetry::Telemetry(
        satcat5::udp::Dispatch* udp,
        const satcat5::udp::Port& dstport,
        bool concat_tiers)
    : satcat5::udp::AddressContainer(udp)
    , satcat5::net::TelemetryAggregator(concat_tiers)
    , satcat5::net::TelemetrySink(this)
{
    connect(satcat5::ip::ADDR_BROADCAST, dstport);
}

TelemetryAggregator::TelemetryAggregator(bool concat_tiers)
    : m_tlm_concat(concat_tiers)
{
    timer_every(100);   // Default 100 msec = 10 Hz polling
}

void TelemetryAggregator::timer_event()
{
    if (!m_tlm_concat) {
        // Per-tier mode: create and send a TelemetryCbor for each tier.
        TelemetryTier* tier = m_tiers.head();
        while (tier) {
            TelemetryCbor cbor;
            tier->telem_poll(cbor);
            telem_send(cbor, tier->m_tier_id);
            tier = m_tiers.next(tier);
        }
    } else {
        // In concatenated mode, send all accumulated data at the end.
        TelemetryCbor cbor;
        TelemetryTier* tier = m_tiers.head();
        while (tier) {
            tier->telem_poll(cbor);
            tier = m_tiers.next(tier);
        }
        telem_send(cbor, 0);
    }
}

void TelemetryAggregator::telem_send(TelemetryCbor& cbor, u32 tier_id)
{
    // Close out the TelemetryCbor object and reuse backing buffer without copy.
    if (!cbor.close()) { return; }
    UsefulBufC encoded = cbor.get_encoded(); // Zero copy

    // Don't bother sending an empty message.
    // Note: Empty CBOR map {...} is exactly one byte.
    if (encoded.len < 2) return;

    // Write data to each TelemetrySink object.
    TelemetrySink* sink = m_sinks.head();
    while (sink) {
        sink->telem_ready(tier_id, encoded.len, encoded.ptr);
        sink = m_sinks.next(sink);
    }
}

TelemetrySink::TelemetrySink(TelemetryAggregator* tlm)
    : m_tlm(tlm)
    , m_next(0)
{
    // Add ourselves to the parent's sink list.
    m_tlm->m_sinks.add(this);
}

#if SATCAT5_ALLOW_DELETION
TelemetrySink::~TelemetrySink()
{
    // Remove ourselves from the parent's list.
    m_tlm->m_sinks.remove(this);
}
#endif // SATCAT5_ALLOW_DELETION

TelemetryTier::TelemetryTier(
        TelemetryAggregator* tlm,
        TelemetrySource* src,
        u32 tier_id,
        unsigned interval_msec)
    : m_tier_id(tier_id)
    , m_next(0)
    , m_tlm(tlm)
    , m_src(src)
    , m_time_interval(0)
    , m_time_count(0)
{
    // Configure timer state.
    set_interval(interval_msec);

    // Add ourselves to the parent's tier list.
    m_tlm->m_tiers.add(this);
}

#if SATCAT5_ALLOW_DELETION
TelemetryTier::~TelemetryTier()
{
    // Remove ourselves from the parent's list.
    m_tlm->m_tiers.remove(this);
}
#endif

void TelemetryTier::set_interval(unsigned interval_msec)
{
    // Update internal time interval.
    m_time_interval = interval_msec;

    // No further action if we're shutting down (interval = 0).
    if (!interval_msec) return;

    // Update the parent's polling interval?
    if (m_tlm->timer_interval() > m_time_interval)
        m_tlm->timer_every(m_time_interval);

    // If user disables and re-enables a given timer, we want to maintain
    // continuity so the next event happens when it would have originally.
    // (This helps ensure once-per-second events stay aligned, for example.)
    m_time_count = m_time_count % m_time_interval;
}

void TelemetryTier::telem_poll(const TelemetryCbor& cbor)
{
    // Always increment the time since last event.
    m_time_count += m_tlm->timer_interval();

    // Elapsed time since the last polling event?
    if (m_time_interval > 0 && m_time_count >= m_time_interval) {
        m_time_count -= m_time_interval;
        m_src->telem_event(m_tier_id, cbor);
    }
}

#endif // SATCAT5_CBOR_ENABLE
