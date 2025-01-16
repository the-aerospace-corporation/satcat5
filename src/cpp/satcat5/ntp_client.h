//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Client for the Network Time Protocol (NTP)
//
// This file implements a combined client and server for the Network Time
// Protocol, version 4 (NTPv4), as defined in IETF RFC-5905.  The client
// follows the simplified rules (aka "SNTP") defined in Section 14, with
// no more than one upstream parent and no peers in the same stratum.
//
// In all modes, the underlying clock is a ptp::TrackingClock object.
// In server mode, the clock is used as a read-only reference.  In client
// mode, the class will issue ptp::Callback notifications that can be used
// to discipline the clock (see also: "ptp_tracking.h").
//
// Server mode is enabled using server_start(...) method.
// If active, the class responds to valid incoming queries immediately,
// with no attempt to maintain state or rate-limiting.  This behavior is
// not suited for untrusted networks and may be changed in future updates.
// Server mode and client mode are not mutually exclusive.
//
// Client mode is activated by calling client_connect(...). While client mode
// is active, the class regularly sends a query to the server; whenever a
// valid reply is received, it notifies any attached ptp::Callback objects.
// (See "ptp_tracking.h" for useful examples.)  The callbacks should adjust
// the underlying clock to bring everything into sync; this class does not
// implement the recommended filter algorithms from Sections 10 and 12.
//
// Broadcast mode and peer-to-peer associations are not currently supported.
//

#pragma once

#include <satcat5/ntp_header.h>
#include <satcat5/polling.h>
#include <satcat5/ptp_source.h>
#include <satcat5/udp_core.h>
#include <satcat5/udp_dispatch.h>

namespace satcat5 {
    namespace ntp {
        // NTP Client and/or Server.
        class Client
            : public satcat5::net::Protocol
            , public satcat5::poll::Timer
            , public satcat5::ptp::Source
        {
        public:
            // Set the reference clock and network interface for this client.
            Client(
                satcat5::ptp::TrackingClock* refclk,
                satcat5::udp::Dispatch* iface);
            ~Client() SATCAT5_OPTIONAL_DTOR;

            // Enable client mode by connecting to the specified server.
            // Polling rate is once every 2^N seconds (see ntp::Header).
            void client_connect(
                const satcat5::ip::Addr& server,
                s8 poll_rate = satcat5::ntp::Header::TIME_1MIN);
            void client_close();
            inline bool client_ok()
                { return m_iface.ready(); }
            void client_set_rate(s8 poll_rate);

            // Enable or disable server mode.
            inline void server_start(u8 stratum)
                { m_stratum = stratum; }

            // Convert reference-clock time to NTP format and back.
            u64 ntp_now() const;
            u64 to_ntp(const satcat5::ptp::Time& t) const;
            satcat5::ptp::Time to_ptp(u64 t) const;

        protected:
            // Inherited event handlers.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            void timer_event() override;

            // Internal event handlers.
            void rcvd_reply(const satcat5::ntp::Header& msg, u64 rxtime);
            bool send_reply(const satcat5::ntp::Header& msg, u64 rxtime);
            bool send_query();

            // Internal state.
            satcat5::ptp::TrackingClock* const m_refclk;
            satcat5::udp::Address m_iface;
            u64 m_reftime;
            u8 m_leap;
            u8 m_stratum;
            s8 m_rate;
        };
    }
}
