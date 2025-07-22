//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_checksum.h>
#include <satcat5/log.h>
#include <satcat5/net_telemetry.h>
#include <satcat5/utils.h>

// Start of conditional compilation...
#if SATCAT5_CBOR_ENABLE

#include <qcbor/qcbor.h>

// Set up basic shortcuts.
using satcat5::eth::crc32;
using satcat5::io::LimitedRead;
using satcat5::util::min_unsigned;

// Thin wrappers for the Ethernet and UDP constructors.
// (Do this first, to avoid namespace conflicts later.)
satcat5::eth::Telemetry::Telemetry(
        satcat5::eth::Dispatch* eth,
        bool concat_tiers)
    : AddressContainer(eth)
    , TelemetryAggregator(concat_tiers)
    , TelemetrySink(this)
{
    // Nothing else to initialize.
}

satcat5::eth::TelemetryRx::TelemetryRx(
        satcat5::eth::Dispatch* iface,
        const satcat5::eth::MacType& type)
    : Protocol(satcat5::net::Type(type.value))
    , satcat5::net::TelemetryRx()
    , m_iface(iface)
{
    m_iface->add(this);
}

#if SATCAT5_ALLOW_DELETION
satcat5::eth::TelemetryRx::~TelemetryRx() {
    m_iface->remove(this);
}
#endif

void satcat5::eth::TelemetryRx::frame_rcvd(LimitedRead& src) {
    telem_packet(src);  // No extra headers, just message contents.
}

satcat5::udp::Telemetry::Telemetry(
        satcat5::udp::Dispatch* udp,
        bool concat_tiers)
    : AddressContainer(udp)
    , TelemetryAggregator(concat_tiers)
    , TelemetrySink(this)
{
    // Nothing else to initialize.
}

satcat5::udp::TelemetryRx::TelemetryRx(
        satcat5::udp::Dispatch* iface,
        const satcat5::udp::Port& port)
    : Protocol(satcat5::net::Type(port.value))
    , satcat5::net::TelemetryRx()
    , m_iface(iface)
{
    m_iface->add(this);
}

#if SATCAT5_ALLOW_DELETION
satcat5::udp::TelemetryRx::~TelemetryRx() {
    m_iface->remove(this);
}
#endif

void satcat5::udp::TelemetryRx::frame_rcvd(LimitedRead& src) {
    telem_packet(src);  // No extra headers, just message contents.
}

// Namespace conflicts resolved, configure remaining shortcuts.
using satcat5::net::TelemetryAggregator;
using satcat5::net::TelemetryCbor;
using satcat5::net::TelemetryKey;
using satcat5::net::TelemetryLogger;
using satcat5::net::TelemetryLoopback;
using satcat5::net::TelemetryRx;
using satcat5::net::TelemetrySink;
using satcat5::net::TelemetrySource;
using satcat5::net::TelemetryTier;
using satcat5::net::TelemetryWatcher;

TelemetryAggregator::TelemetryAggregator(bool concat_tiers)
    : m_tlm_concat(concat_tiers)
{
    timer_every(100);   // Default 100 msec = 10 Hz polling
}

void TelemetryAggregator::timer_event() {
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

void TelemetryAggregator::telem_send(TelemetryCbor& cbor, u32 tier_id) {
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

TelemetryKey::TelemetryKey(const char* label)
    : key(label)
    , hash(crc32(strlen(label), label))
{
    // Nothing else to initialize.
}

TelemetryLogger::TelemetryLogger(TelemetryRx* rx, const char* kstr)
    : TelemetryWatcher(rx)
{
    if (kstr) m_filter = TelemetryKey(kstr).hash;
}

TelemetryLogger::TelemetryLogger(TelemetryRx* rx, u32 key)
    : TelemetryWatcher(rx)
{
    m_filter = key;
}

void TelemetryLogger::telem_rcvd(
    u32 key, const QCBORItem& item,
    QCBORDecodeContext* cbor)
{
    // If a filter is configured, ignore non-matching keys.
    if (m_filter && m_filter.value() != key) return;

    // Log the received key and value.
    satcat5::log::Log(satcat5::log::INFO, "Telemetry")
        .write_obj(satcat5::io::CborLogger(item));
}

TelemetryLoopback::TelemetryLoopback(TelemetryAggregator* src, TelemetryRx* dst)
    : TelemetrySink(src)
    , m_dst(dst)
{
    // Nothing else to initialize.
}

void TelemetryLoopback::telem_ready(u32 tier_id, unsigned nbytes, const void* data) {
    satcat5::io::ArrayRead rd(nbytes, data);
    satcat5::io::LimitedRead lrd(&rd);
    if (m_dst) m_dst->telem_packet(lrd);
}

void TelemetryRx::telem_packet(LimitedRead& src) {
    // Copy input data to a working buffer.
    u8 buff[SATCAT5_QCBOR_BUFFER];
    unsigned len = min_unsigned(sizeof(buff), src.get_read_ready());
    src.read_bytes(len, buff);

    // Create QCBOR parser and confirm message contains a dictionary.
    QCBORDecodeContext cbor;
    QCBORDecode_Init(&cbor, {buff, len}, QCBOR_DECODE_MODE_NORMAL);
    QCBORItem item;
    QCBORDecode_EnterMap(&cbor, &item);
    if (QCBORDecode_GetError(&cbor) != QCBOR_SUCCESS) return;

    // Iterate over the dictionary contents...
    while (1) {
        // Peek at the next item. If it's an array or map, enter it now.
        // Otherwise, read and consume self-contained items with GetNext().
        int errcode = QCBORDecode_PeekNext(&cbor, &item);
        if (errcode || item.uNestingLevel < 1) break;
        if (item.uDataType == QCBOR_TYPE_ARRAY) {
            QCBORDecode_EnterArray(&cbor, &item);
            telem_item(&cbor, item);
            QCBORDecode_ExitArray(&cbor);
        } else if (item.uDataType == QCBOR_TYPE_MAP) {
            QCBORDecode_EnterMap(&cbor, &item);
            telem_item(&cbor, item);
            QCBORDecode_ExitMap(&cbor);
        } else {
            QCBORDecode_GetNext(&cbor, &item);
            telem_item(nullptr, item);
        }
    }
}

void TelemetryRx::telem_item(QCBORDecodeContext* cbor, const QCBORItem& item) {
    // Ignore items at the wrong nesting level.
    if (item.uNestingLevel > 1) return;

    // Determine the integer key for this object.
    u32 key = u32(item.label.int64);
    if (item.uLabelType == QCBOR_TYPE_BYTE_STRING ||
        item.uLabelType == QCBOR_TYPE_TEXT_STRING) {
        key = crc32(item.label.string.len, item.label.string.ptr);
    }

    // Notify each registered TelemetryWatcher.
    // Complex data-structures provide the "cbor" pointer for further parsing.
    // To prevent side-effects with multiple watchers, rewind after each call.
    TelemetryWatcher* callback = m_watchers.head();
    while (callback) {
        callback->telem_rcvd(key, item, cbor);
        callback = m_watchers.next(callback);
        if (cbor) QCBORDecode_Rewind(cbor);
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
TelemetrySink::~TelemetrySink() {
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
TelemetryTier::~TelemetryTier() {
    // Remove ourselves from the parent's list.
    m_tlm->m_tiers.remove(this);
}
#endif

void TelemetryTier::send_now() {
    // Immediately gather data, then send it.
    TelemetryCbor cbor;
    m_src->telem_event(m_tier_id, cbor);
    m_tlm->telem_send(cbor, m_tier_id);
}

void TelemetryTier::set_interval(unsigned interval_msec) {
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

void TelemetryTier::telem_poll(TelemetryCbor& cbor) {
    // Always increment the time since last event.
    m_time_count += m_tlm->timer_interval();

    // Elapsed time since the last polling event?
    if (m_time_interval > 0 && m_time_count >= m_time_interval) {
        m_time_count -= m_time_interval;
        m_src->telem_event(m_tier_id, cbor);
    }
}

TelemetryWatcher::TelemetryWatcher(TelemetryRx* rx)
    : m_rx(rx)
    , m_next(nullptr)
{
    m_rx->add_watcher(this);
}

#if SATCAT5_ALLOW_DELETION
TelemetryWatcher::~TelemetryWatcher() {
    m_rx->remove_watcher(this);
}
#endif

#endif // SATCAT5_CBOR_ENABLE
