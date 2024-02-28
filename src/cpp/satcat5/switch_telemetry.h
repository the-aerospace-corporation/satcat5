//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
// Diagnostic telemetry for a SatCat5 switch
//
// The SwitchTelemetry class reports state-of-health telemetry for a SatCat5
// switch, using the CBOR telemetry API (net_telemetry.h).  Status is polled
// through the SwitchConfig interface (switch_cfg.h), and optionally through
// the NetworkStats interface (cfgbus_stats.h).  If the latter is provided,
// then this class will call "refresh_now()", which resets hardware counters
// for traffic statistics.
//
// Telemetry is divided into tiers, with independent rates:
//  Tier 1: Switch status, including MAC table information.
//          (Default once every 30 seconds.)
//  Tier 2: Trafic statistics, including per-port counters if available.
//          (Default once every second.)
//

#pragma once

#include <satcat5/net_telemetry.h>

// Enable this feature? (See types.h)
#if SATCAT5_CBOR_ENABLE

namespace satcat5 {
    namespace eth {
        class SwitchTelemetry final : public satcat5::net::TelemetrySource
        {
        public:
            // Constructor links to a specific data source.
            // Note: No data is sent until user calls connect(...).
            SwitchTelemetry(
                satcat5::net::TelemetryAggregator* tlm,
                satcat5::eth::SwitchConfig* cfg,
                satcat5::cfg::NetworkStats* stats = 0);

            // Adjust the reporting interval for each tier.
            inline void set_interval_cfg(unsigned interval_msec)
                { m_tier1.set_interval(interval_msec); }
            inline void set_interval_stats(unsigned interval_msec)
                { m_tier2.set_interval(interval_msec); }

        protected:
            // Required API from net::TelemetrySource.
            void telem_event(u32 tier_id, const satcat5::net::TelemetryCbor& cbor) override;

            // Internal state.
            satcat5::eth::SwitchConfig* const m_cfg;
            satcat5::cfg::NetworkStats* const m_stats;
            satcat5::net::TelemetryTier m_tier1;
            satcat5::net::TelemetryTier m_tier2;
        };
    }
}

#endif // SATCAT5_CBOR_ENABLE
