//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
// Diagnostic telemetry for Precision Time Protocol (PTP) clients
//
// The ptp::Telemetry class is an optional module used to report state
// information for the ptp::Client class.  This telemetry is used for
// diagnostics, monitoring, testing, etc.
//
// When enabled, CBOR-encoded telemetry is forwarded over UDP to the
// designated IP-address and port.  A separate Python utility logs
// and analyzes the information.
//

#pragma once

#include <satcat5/ptp_measurement.h>
#include <satcat5/udp_core.h>

namespace satcat5 {
    namespace ptp {
        class Logger final : public satcat5::ptp::Callback
        {
        public:
            // Constructor links to a specific data source.
            explicit Logger(
                satcat5::ptp::Client* client,
                const satcat5::ptp::TrackingClock* track = 0);
            ~Logger() {}

            // Required API from ptp::Callback:
            void ptp_ready(const satcat5::ptp::Measurement& data) override;

        protected:
            const satcat5::ptp::TrackingClock* const m_track;
        };

        class Telemetry final : public satcat5::ptp::Callback
        {
        public:
            // Constructor links to a specific data source.
            // Note: No data is sent until user calls connect(...).
            Telemetry(
                satcat5::ptp::Client* client,
                satcat5::udp::Dispatch* iface,
                const satcat5::ptp::TrackingClock* track = 0);
            ~Telemetry() {}

            // Set the destination address.
            inline void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport = satcat5::udp::PORT_CBOR_TLM)
                { m_addr.connect(dstaddr, dstport, 0); }
            inline void close()
                { m_addr.close(); }

            // Set the level of detail to include.
            inline void set_level(unsigned level)
                { m_level = level; }

        protected:
            // Required API from ptp::Callback:
            void ptp_ready(const satcat5::ptp::Measurement& data) override;

            // Internal state.
            const satcat5::ptp::TrackingClock* const m_track;
            satcat5::udp::Address m_addr;
            unsigned m_level;
        };
    }
}
