//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_stats.h>
#include <satcat5/switch_cfg.h>
#include <satcat5/switch_telemetry.h>

// Enable this feature? (See types.h)
#if SATCAT5_CBOR_ENABLE

using satcat5::cfg::NetworkStats;
using satcat5::cfg::TrafficStats;
using satcat5::eth::SwitchConfig;
using satcat5::eth::SwitchTelemetry;
using satcat5::net::TelemetryCbor;

static void copy_mactbl_array(_QCBOREncodeContext* cbor, SwitchConfig* cfg)
{
    unsigned port_idx;
    satcat5::eth::MacAddr mac_addr;
    unsigned table_size = cfg->mactbl_size();

    // Write a CBOR array containing MAC table information.
    QCBOREncode_OpenArray(cbor);
    for (unsigned tbl_idx = 0 ; tbl_idx < table_size ; ++tbl_idx) {
        if (cfg->mactbl_read(tbl_idx, port_idx, mac_addr)) {
            // Each table entry is a paired MAC address + port-index.
            QCBOREncode_OpenArray(cbor);
            QCBOREncode_AddBytes(cbor, {mac_addr.addr, 6});
            QCBOREncode_AddUInt64(cbor, port_idx);
            QCBOREncode_CloseArray(cbor);
        }
    }
    QCBOREncode_CloseArray(cbor);
}

static void copy_traffic_array(_QCBOREncodeContext* cbor, unsigned port_count, NetworkStats* stats)
{
    // Write a CBOR array containing traffic statistics for each port.
    QCBOREncode_OpenArray(cbor);
    for (unsigned a = 0 ; a < port_count ; ++a) {
        // Read port data, then write out a CBOR key/value dictionary.
        TrafficStats data = stats->get_port(a);
        QCBOREncode_OpenMap(cbor);
        QCBOREncode_AddUInt64ToMap(cbor, "rxb", data.rcvd_bytes);
        QCBOREncode_AddUInt64ToMap(cbor, "rxf", data.rcvd_frames);
        QCBOREncode_AddUInt64ToMap(cbor, "txb", data.sent_bytes);
        QCBOREncode_AddUInt64ToMap(cbor, "txf", data.sent_frames);
        if (data.errct_mac)     QCBOREncode_AddUInt64ToMap(cbor, "err_mac",     data.errct_mac);
        if (data.errct_ovr_tx)  QCBOREncode_AddUInt64ToMap(cbor, "err_ovr_tx",  data.errct_ovr_tx);
        if (data.errct_ovr_rx)  QCBOREncode_AddUInt64ToMap(cbor, "err_ovr_rx",  data.errct_ovr_rx);
        if (data.errct_pkt)     QCBOREncode_AddUInt64ToMap(cbor, "err_pkt",     data.errct_pkt);
        if (data.errct_ptp_tx)  QCBOREncode_AddUInt64ToMap(cbor, "err_ptp_tx",  data.errct_ptp_tx);
        if (data.errct_ptp_rx)  QCBOREncode_AddUInt64ToMap(cbor, "err_ptp_rx",  data.errct_ptp_rx);
        QCBOREncode_CloseMap(cbor);
    }
    QCBOREncode_CloseArray(cbor);
}

SwitchTelemetry::SwitchTelemetry(
        satcat5::net::TelemetryAggregator* tlm,
        satcat5::eth::SwitchConfig* cfg,
        satcat5::cfg::NetworkStats* stats)
    : m_cfg(cfg)        // Required
    , m_stats(stats)    // Optional
    , m_tier1(tlm, this, 1, 30000)
    , m_tier2(tlm, this, 2, 1000)
{
    // Nothing else to initialize.
}

void SwitchTelemetry::telem_event(u32 tier_id, const TelemetryCbor& cbor)
{
    if (tier_id == 1) {
        // Switch status information.
        u32 pmask = m_cfg->get_promiscuous_mask();
        cbor.add_item("bmask", m_cfg->get_miss_mask());
        if (pmask) cbor.add_item("pmask", pmask);
        // Write the MAC table contents as a nested array.
        QCBOREncode_AddSZString(cbor.cbor, "mactbl");
        copy_mactbl_array(cbor.cbor, m_cfg);
    } else {
        // Total traffic statistics from the switch itself.
        u16 filter = m_cfg->get_traffic_filter();
        if (filter) cbor.add_item("traffic_etype_filter", filter);
        cbor.add_item("traffic_total_frm", m_cfg->get_traffic_count());
        // Per-port counters, if available.
        if (m_stats) {
            m_stats->refresh_now();
            QCBOREncode_AddSZString(cbor.cbor, "traffic_by_port");
            copy_traffic_array(cbor.cbor, m_cfg->port_count(), m_stats);
        }
    }
}

#endif // SATCAT5_CBOR_ENABLE
