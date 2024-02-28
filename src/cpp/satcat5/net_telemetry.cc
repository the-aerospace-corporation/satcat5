//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/net_telemetry.h>
#include <satcat5/utils.h>

// Start of conditional compilation...
#if SATCAT5_CBOR_ENABLE

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
    // Initialize the QCBOR encoder.
    QCBOREncodeContext qcbor;
    telem_init(&qcbor);

    // Poll each of the contained tier objects.
    TelemetryCbor cbor = {&qcbor};
    TelemetryTier* tier = m_tiers.head();
    while (tier) {
        // Write out telemetry for this tier.
        tier->telem_poll(cbor);
        // In per-tier mode, always send and reset.
        if (!m_tlm_concat) {
            telem_send(&qcbor, tier->m_tier_id);
            telem_init(&qcbor);
        }
        // Move to next list item...
        tier = m_tiers.next(tier);
    }

    // In concatenated mode, send all accumulated data at the end.
    if (m_tlm_concat) {
        telem_send(&qcbor, 0);
    }
}

void TelemetryAggregator::telem_init(_QCBOREncodeContext* cbor)
{
    // Initialize or re-initialize the encoder state.
    QCBOREncode_Init(cbor, UsefulBuf_FROM_BYTE_ARRAY(m_buff));

    // Open the key/value dictionary for subsequent telemetry.
    QCBOREncode_OpenMap(cbor);
}

void TelemetryAggregator::telem_send(_QCBOREncodeContext* cbor, u32 tier_id)
{
    // Close out the QCBOR object.
    UsefulBufC encoded;
    QCBOREncode_CloseMap(cbor);
    QCBORError error = QCBOREncode_Finish(cbor, &encoded);
    if (error) return;

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

void TelemetryCbor::add_array(s64 key, u32 len, const s8* value) const
{
    QCBOREncode_AddInt64(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(s64 key, u32 len, const u8* value) const
{
    QCBOREncode_AddInt64(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddUInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(s64 key, u32 len, const s16* value) const
{
    QCBOREncode_AddInt64(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(s64 key, u32 len, const u16* value) const
{
    QCBOREncode_AddInt64(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddUInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(s64 key, u32 len, const s32* value) const
{
    QCBOREncode_AddInt64(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(s64 key, u32 len, const u32* value) const
{
    QCBOREncode_AddInt64(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddUInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(s64 key, u32 len, const s64* value) const
{
    QCBOREncode_AddInt64(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(s64 key, u32 len, const u64* value) const
{
    QCBOREncode_AddInt64(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddUInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(s64 key, u32 len, const float* value) const
{
    QCBOREncode_AddInt64(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddFloat(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(const char* key, u32 len, const s8* value) const
{
    QCBOREncode_AddSZString(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(const char* key, u32 len, const u8* value) const
{
    QCBOREncode_AddSZString(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddUInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(const char* key, u32 len, const s16* value) const
{
    QCBOREncode_AddSZString(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(const char* key, u32 len, const u16* value) const
{
    QCBOREncode_AddSZString(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddUInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(const char* key, u32 len, const s32* value) const
{
    QCBOREncode_AddSZString(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(const char* key, u32 len, const u32* value) const
{
    QCBOREncode_AddSZString(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddUInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(const char* key, u32 len, const s64* value) const
{
    QCBOREncode_AddSZString(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(const char* key, u32 len, const u64* value) const
{
    QCBOREncode_AddSZString(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddUInt64(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

void TelemetryCbor::add_array(const char* key, u32 len, const float* value) const
{
    QCBOREncode_AddSZString(cbor, key);
    QCBOREncode_OpenArray(cbor);
    for (u32 a = 0 ; a < len ; ++a)
        QCBOREncode_AddFloat(cbor, value[a]);
    QCBOREncode_CloseArray(cbor);
}

#endif // SATCAT5_CBOR_ENABLE
