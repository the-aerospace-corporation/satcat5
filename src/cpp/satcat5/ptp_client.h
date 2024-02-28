//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Client for the IEEE 1588-2019 Precision Time Protocol (PTP)
//
// This file implements a simple "Client" endpoint for the Precision Time
// Protocol, which may act as either master or slave depending on mode.
// It uses a single network port and acts as an "Ordinary Clock" as defined
// in IEEE 1588-2019 Section 9.
//

#pragma once

#include <satcat5/io_readable.h>
#include <satcat5/polling.h>
#include <satcat5/ptp_dispatch.h>
#include <satcat5/ptp_header.h>
#include <satcat5/ptp_measurement.h>

namespace satcat5 {
    namespace ptp {
        // Configure the operating mode of a given Client.
        // TODO: Add support for auto-config.
        enum class ClientMode {
            DISABLED,       // Complete shutdown (Section 9.2.5)
            MASTER_L2,      // Master only, Ethernet mode (Section 9.2.2.1)
            MASTER_L3,      // Master only, UDP mode (Section 9.2.2.1)
            SLAVE_ONLY,     // Slave only (Section 9.2.2.2)
            PASSIVE         // Passive mode (for Pdelay) (Section 9.2.5)
        };

        // Internal states correspond to Section 9.2.5 and Table 27, except that
        // INITIALIZING and certain optional states (Section 17.7.2) are ignored.
        // State is visible for diagnostics but cannot be changed directly.
        enum class ClientState {
            DISABLED,       // Manual shutdown
            LISTENING,      // Waiting for ANNOUNCE to select a master
            MASTER,         // Actively providing time to other clients
            PASSIVE,        // Passively responding to peer requests
            SLAVE,          // Actively synchronizing local clock to master
        };

        // Convert the above to human-readable strings.
        const char* to_string(satcat5::ptp::ClientMode mode);
        const char* to_string(satcat5::ptp::ClientState state);

        // Top-level object representing a complete PTP Client.
        class Client
            : public satcat5::poll::Timer
            , public satcat5::ptp::Source
        {
        public:
            // Set the network interface for this client.
            Client(
                satcat5::ptp::Interface* ptp_iface,
                satcat5::ip::Dispatch* ip_dispatch,
                satcat5::ptp::ClientMode mode = ClientMode::DISABLED);
            ~Client() SATCAT5_OPTIONAL_DTOR;

            // Clock configuration accessors.
            inline void set_clock(const satcat5::ptp::ClockInfo& clk)
                { m_clock_local = clk; }
            inline satcat5::ptp::ClockInfo get_clock() const
                { return m_clock_local; }

            // Mode and state accessors.
            void set_mode(satcat5::ptp::ClientMode mode);
            inline satcat5::ip::Dispatch* get_iface() const {return m_iface.iface();}
            inline satcat5::ptp::ClientMode get_mode() const {return m_mode;}
            inline satcat5::ptp::ClientState get_state() const {return m_state;}

            // Master only: Set the SYNC message rate to 2^N / sec.
            void set_sync_rate(u8 rate);

            // Set the pdelay message rate to 0.9 x 2^N / sec.
            void set_pdelay_rate(u8 rate);

            // Send a unicast Sync message to the designated address.
            // (Unicast allows higher message rates than broadcast mode.)
            bool send_sync_unicast(
                const satcat5::eth::MacAddr& mac,
                const satcat5::ip::Addr& ip = satcat5::ip::ADDR_NONE);

            // Dispatch calls this method for each incoming packet.
            void ptp_rcvd(satcat5::io::LimitedRead& rd);

        protected:
            // Timer event handler.
            void timer_event() override;

            // Timer setup based on current state.
            void timer_reset();

            // Handlers for specific incoming messages.
            void rcvd_announce(
                const satcat5::ptp::Header& hdr,
                satcat5::io::LimitedRead& rd);
            void rcvd_delay_req(
                const satcat5::ptp::Header& hdr,
                satcat5::io::LimitedRead& rd);
            void rcvd_pdelay_req(
                const Header& hdr,
                satcat5::io::LimitedRead& rd);
            void rcvd_delay_resp(
                const satcat5::ptp::Header& hdr,
                satcat5::io::LimitedRead& rd);
            void rcvd_pdelay_resp(
                const satcat5::ptp::Header& hdr,
                satcat5::io::LimitedRead& rd);
            void rcvd_follow_up(
                const satcat5::ptp::Header& hdr,
                satcat5::io::LimitedRead& rd);
            void rcvd_pdelay_follow_up(
                const satcat5::ptp::Header& hdr,
                satcat5::io::LimitedRead& rd);
            void rcvd_sync(
                const satcat5::ptp::Header& hdr,
                satcat5::io::LimitedRead& rd);
            void rcvd_unexpected(
                const satcat5::ptp::Header& hdr);

            // Create PTP message header of the given type.
            satcat5::ptp::Header make_header(u8 type, u16 seq_id);

            // Generate and send specific outgoing messages.
            void send_announce_maybe();
            bool send_announce();
            bool send_delay_req(const satcat5::ptp::Header& ref);
            bool send_pdelay_req();
            bool send_delay_resp(const satcat5::ptp::Header& ref);
            bool send_pdelay_resp(const satcat5::ptp::Header& ref);
            bool send_pdelay_follow_up(const satcat5::ptp::Header& ref);
            bool send_follow_up(satcat5::ptp::DispatchTo addr);
            bool send_sync(satcat5::ptp::DispatchTo addr);

            // PTP dispatch object.
            satcat5::ptp::Dispatch m_iface;

            // Other working state.
            satcat5::ptp::ClientMode m_mode;
            satcat5::ptp::ClientState m_state;
            satcat5::ptp::MeasurementCache m_cache;
            satcat5::ptp::ClockInfo m_clock_local;
            satcat5::ptp::ClockInfo m_clock_remote;
            satcat5::ptp::PortId m_current_source;
            unsigned m_announce_count;
            unsigned m_announce_every;
            unsigned m_sync_rate;
            unsigned m_pdelay_rate;
            u16 m_announce_id;
            u16 m_sync_id;
            u16 m_pdelay_id;
        };

        // Helper classes for sending unicast Sync messages on a separate timer.
        // (Section 9.5.9.2 allows this rate to be as high as needed.)
        class SyncUnicastL2 : public satcat5::poll::Timer {
        public:
            // Create this object and manage its connection.
            explicit SyncUnicastL2(satcat5::ptp::Client* client);
            inline void connect(const satcat5::eth::MacAddr& addr)
                { m_dstmac = addr; }

        protected:
            // Call inherited method timer_every(...) to set message rate.
            void timer_event();

            satcat5::ptp::Client* const m_client;
            satcat5::eth::MacAddr m_dstmac;
        };

        class SyncUnicastL3 : public satcat5::poll::Timer
        {
        public:
            // Create this object and manage its connection.
            explicit SyncUnicastL3(satcat5::ptp::Client* client);
            inline void connect(const satcat5::ip::Addr& dstaddr)
                { m_addr.connect(dstaddr); }
            inline void close()
                { m_addr.close(); }

        protected:
            // Call inherited method timer_every(...) to set message rate.
            void timer_event();
            satcat5::ptp::Client* const m_client;
            satcat5::ip::Address m_addr;
        };
    }
}
