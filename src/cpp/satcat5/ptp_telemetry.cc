//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/ptp_client.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/ptp_telemetry.h>

// Set the size of the working buffer.
#ifndef SATCAT5_QCBOR_BUFFER
#define SATCAT5_QCBOR_BUFFER 1500
#endif

using satcat5::ptp::Logger;
using satcat5::ptp::Telemetry;

Logger::Logger(
    satcat5::ptp::Client* client,
    const satcat5::ptp::TrackingClock* track)
    : satcat5::ptp::Callback(client)
    , m_track(track)
{
    // Nothing else to initialize.
}

void Logger::ptp_ready(const satcat5::ptp::Measurement& data)
{
    const char* state = m_client ?
        satcat5::ptp::to_string(m_client->get_state()) : "Unknown";
    s64 mpd = data.mean_path_delay().delta_nsec();
    s64 ofm = data.offset_from_master().delta_nsec();
    s64 sub = data.offset_from_master().delta_subns();

    satcat5::log::Log msg(satcat5::log::INFO, "PtpClient state", state);
    msg.write("\n  meanPathDelay(ns)").write10(mpd);
    msg.write("\n  offsetFromMaster(ns)").write10(ofm);
    msg.write("\n  offsetFromMaster(subns)").write10(sub);
    if (m_track) msg.write("\n  tuningOffset(arb)").write10(m_track->get_rate());
}

Telemetry::Telemetry(
    satcat5::ptp::Client* client,
    satcat5::udp::Dispatch* iface,
    const satcat5::ptp::TrackingClock* track)
    : satcat5::ptp::Callback(client)
    , m_track(track)
    , m_addr(iface)
    , m_level(0)
{
    // Nothing else to initialize.
}

// Is CBOR enabled? (See types.h)
#if SATCAT5_CBOR_ENABLE
#include <qcbor/qcbor_encode.h>

void Telemetry::ptp_ready(const satcat5::ptp::Measurement& data)
{
    // Before we start, check if UDP object is configured.
    if (!m_addr.ready()) return;

    // Initialize CBOR encoder and its working buffer.
    u8 buff[SATCAT5_QCBOR_BUFFER];
    QCBOREncodeContext cbor;
    QCBOREncode_Init(&cbor, UsefulBuf_FROM_BYTE_ARRAY(buff));
    QCBOREncode_OpenMap(&cbor);

    // Write telemetry items at various verbosity levels:
    QCBOREncode_AddInt64ToMap(&cbor, "mean_path_delay",
        data.mean_path_delay().delta_subns());
    QCBOREncode_AddInt64ToMap(&cbor, "offset_from_master",
        data.offset_from_master().delta_subns());

    if (m_client) {
        QCBOREncode_AddSZStringToMap(&cbor, "client_state",
            satcat5::ptp::to_string(m_client->get_state()));
    }

    if (m_track) {
        QCBOREncode_AddInt64ToMap(&cbor, "tuning_offset", m_track->get_rate());
    }

    if (m_level > 0) {
        QCBOREncode_AddInt64ToMap (&cbor, "t1_secs",  data.t1.field_secs());
        QCBOREncode_AddUInt64ToMap(&cbor, "t1_subns", data.t1.field_subns());
        QCBOREncode_AddInt64ToMap (&cbor, "t2_secs",  data.t2.field_secs());
        QCBOREncode_AddUInt64ToMap(&cbor, "t2_subns", data.t2.field_subns());
        QCBOREncode_AddInt64ToMap (&cbor, "t3_secs",  data.t3.field_secs());
        QCBOREncode_AddUInt64ToMap(&cbor, "t3_subns", data.t3.field_subns());
        QCBOREncode_AddInt64ToMap (&cbor, "t4_secs",  data.t4.field_secs());
        QCBOREncode_AddUInt64ToMap(&cbor, "t4_subns", data.t4.field_subns());
    }

    // Close out the QCBOR object.
    UsefulBufC encoded;
    QCBOREncode_CloseMap(&cbor);
    QCBORError error = QCBOREncode_Finish(&cbor, &encoded);
    if (error) return;

    // Send the encoded UDP datagram.
    satcat5::io::Writeable* wr = m_addr.open_write(encoded.len);
    if (wr) {
        wr->write_bytes(encoded.len, encoded.ptr);
        wr->write_finalize();
    }
}

#else

void Telemetry::ptp_ready(const satcat5::ptp::Measurement& data)
{
    // Dummy method in case CBOR is disabled.
}

#endif // SATCAT5_CBOR_ENABLE
