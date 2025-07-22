//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Client for the IEEE 1588-2019 Precision Time Protocol (PTP)

#pragma once

#include <satcat5/io_readable.h>
#include <satcat5/list.h>
#include <satcat5/polling.h>
#include <satcat5/ptp_dispatch.h>
#include <satcat5/ptp_header.h>
#include <satcat5/ptp_measurement.h>
#include <satcat5/ptp_source.h>

namespace satcat5 {
    namespace ptp {
        //! Configure the operating mode of a given ptp::Client.
        enum class ClientMode {
            DISABLED,       // Complete shutdown (Section 9.2.5)
            MASTER_L2,      // Master only, Ethernet mode (Section 9.2.2.1)
            MASTER_L3,      // Master only, UDP mode (Section 9.2.2.1)
            SLAVE_ONLY,     // Slave only, ordinary mode (Section 9.2.2.2)
            SLAVE_SPTP,     // Slave only, SPTP mode
            PASSIVE,        // Passive mode (for Pdelay) (Section 9.2.5)
        };

        //! Operational state for a given ptp::Client.
        //! Internal states correspond to Section 9.2.5 and Table 27, except
        //! that INITIALIZING and certain optional states (Section 17.7.2)
        //! are ignored. State is visible for diagnostics but cannot be
        //! changed directly.
        enum class ClientState {
            DISABLED,       // Manual shutdown
            LISTENING,      // Waiting for ANNOUNCE to select a master
            MASTER,         // Actively providing time to other clients
            PASSIVE,        // Passively responding to peer requests
            SLAVE,          // Actively synchronizing local clock to master
        };

        //! Convert ClientMode to a human-readable string.
        const char* to_string(satcat5::ptp::ClientMode mode);
        //! Convert ClientState to a human-readable string.
        const char* to_string(satcat5::ptp::ClientState state);

        //! Client for the IEEE 1588-2019 Precision Time Protocol (PTP)
        //!
        //! This file implements a simple "Client" endpoint for the Precision
        //! Time Protocol, which may act as either master or slave depending
        //! on mode. It uses a single network port and acts as an "Ordinary
        //! Clock" as defined in IEEE 1588-2019 Section 9.  Other modes such
        //! as boundary clocks may be added in a future release.
        //!
        //! This client also supports Meta's proposed "Simple Precision Time Protocol"
        //! (SPTP) extention, which reduces overhead for unicast PTP exchanges.
        //!  https://engineering.fb.com/2024/02/07/production-engineering/simple-precision-time-protocol-sptp-meta/
        //!  https://ieeexplore.ieee.org/document/10296989
        //!
        //! Long-term feature wishlist:
        //!  * Support for automatic configuration and master/grandmaster selection.
        //!  * Support for asymmetric handshakes (i.e., many SYNC, few DELAY_REQ).
        class Client
            : public satcat5::poll::Timer
            , public satcat5::ptp::Source
        {
        public:
            //! Set the network interface for this client.
            Client(
                satcat5::ptp::Interface* ptp_iface,
                satcat5::ip::Dispatch* ip_dispatch,
                satcat5::ptp::ClientMode mode = ClientMode::DISABLED);
            ~Client() SATCAT5_OPTIONAL_DTOR;

            //! Set clock information for outgoing ANNOUNCE messages.
            inline void set_clock(const satcat5::ptp::ClockInfo& clk)
                { m_clock_local = clk; }
            //! Get local clock information.
            inline satcat5::ptp::ClockInfo get_clock() const
                { return m_clock_local; }
            //! Read the current time from the network interface.
            inline satcat5::ptp::Time get_time_now()
                { return m_iface.ptp_time_now(); }

            //! Mode and state accessors.
            //!@{
            void set_mode(satcat5::ptp::ClientMode mode);
            inline satcat5::ip::Dispatch* get_iface() const {return m_iface.iface();}
            inline satcat5::ptp::ClientMode get_mode() const {return m_mode;}
            inline satcat5::ptp::ClientState get_state() const {return m_state;}
            inline satcat5::ptp::PortId get_source() const {return m_current_source;}
            //!@}

            //! Master only: Set the SYNC message rate to 2^N / sec.
            //! Range 0-8. Negative rates disable outgoing SYNC messages.
            void set_sync_rate(int rate);

            //! Set the pdelay message rate to 0.9 x 2^N / sec.
            //! Range 0-8. Negative rates disable outgoing PDELAY_REQ messages.
            void set_pdelay_rate(int rate);

            //! Send a unicast Sync message to the designated address.
            //! Unicast allows higher message rates than broadcast mode,
            //! and ignores the rate parameter from `set_sync_rate`.
            bool send_sync_unicast(
                const satcat5::eth::MacAddr& mac,
                const satcat5::ip::Addr& ip = satcat5::ip::ADDR_NONE,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            //! Dispatch calls this method for each incoming packet.
            void ptp_rcvd(satcat5::io::LimitedRead& rd);

        protected:
            // Timer event handler.
            void timer_event() override;

            // Timer setup based on current state.
            void timer_reset();

            // Handling for various error events.
            void cache_miss();
            void client_timeout();

            // Handlers for TLV and measurement events.
            unsigned tlv_send(
                const satcat5::ptp::Header& hdr,
                satcat5::io::Writeable* wr);
            void notify_if_complete(
                const satcat5::ptp::Measurement* meas);

            // Handlers for specific incoming messages.
            void rcvd_announce(
                const satcat5::ptp::Header& hdr,
                satcat5::io::ArrayRead& rd);
            void rcvd_delay_req(
                const satcat5::ptp::Header& hdr,
                satcat5::io::ArrayRead& rd);
            void rcvd_pdelay_req(
                const Header& hdr,
                satcat5::io::ArrayRead& rd);
            void rcvd_delay_resp(
                const satcat5::ptp::Header& hdr,
                satcat5::io::ArrayRead& rd);
            void rcvd_pdelay_resp(
                const satcat5::ptp::Header& hdr,
                satcat5::io::ArrayRead& rd);
            void rcvd_follow_up(
                const satcat5::ptp::Header& hdr,
                satcat5::io::ArrayRead& rd);
            void rcvd_pdelay_follow_up(
                const satcat5::ptp::Header& hdr,
                satcat5::io::ArrayRead& rd);
            void rcvd_sync(
                const satcat5::ptp::Header& hdr,
                satcat5::io::ArrayRead& rd);
            void rcvd_unexpected(
                const satcat5::ptp::Header& hdr);

            // Create PTP message header of the given type.
            satcat5::ptp::Header make_header(u8 type, u16 seq_id);

            // Generate and send specific outgoing messages.
            // TODO: Update ALL messages to use ptp::Header objects???
            void send_announce_maybe();
            bool send_announce();
            bool send_sync(
                satcat5::ptp::DispatchTo addr,
                u16 seq_id, u16 flags = 0, u64 tref = 0);
            bool send_follow_up(
                satcat5::ptp::DispatchTo addr,
                u16 seq_id, u16 flags = 0, u64 tref = 0);
            void send_delay_req_sptp();
            bool send_delay_req(u16 seq_id, u16 flags = 0);
            bool send_delay_resp(const satcat5::ptp::Header& ref);
            bool send_pdelay_req();
            bool send_pdelay_resp(const satcat5::ptp::Header& ref);
            bool send_pdelay_follow_up(const satcat5::ptp::Header& ref);

            // PTP dispatch object.
            satcat5::ptp::Dispatch m_iface;

            // List of registered TLV handlers (see "ptp_tlv.h").
            friend satcat5::ptp::TlvHandler;
            satcat5::util::List<satcat5::ptp::TlvHandler> m_tlv_list;

            // Other working state.
            satcat5::ptp::ClientMode m_mode;
            satcat5::ptp::ClientState m_state;
            satcat5::ptp::MeasurementCache m_cache;
            satcat5::ptp::ClockInfo m_clock_local;
            satcat5::ptp::ClockInfo m_clock_remote;
            satcat5::ptp::PortId m_current_source;
            unsigned m_announce_count;
            unsigned m_announce_every;
            unsigned m_cache_wdog;
            unsigned m_request_wdog;
            int m_sync_rate;
            int m_pdelay_rate;
            u16 m_announce_id;
            u16 m_sync_id;
            u16 m_pdelay_id;
        };

        //! Helper class for sending unicast Sync messages to an L2 client.
        //! This helper class sends unicast Sync messages on a separate timer.
        //! IEEE1588 Section 9.5.9.2 allows this rate to be as high as needed,
        //! if client and server administrators agree on the configuration.
        class SyncUnicastL2 : public satcat5::poll::Timer {
        public:
            //! Create this object.
            explicit SyncUnicastL2(satcat5::ptp::Client* client);

            //! Set the destination for outgoing SYNC messages.
            inline void connect(const satcat5::eth::MacAddr& addr)
                { m_dstmac = addr; }

        protected:
            // Call inherited method timer_every(...) to set message rate.
            void timer_event();

            satcat5::ptp::Client* const m_client;
            satcat5::eth::MacAddr m_dstmac;
        };

        //! Helper class for sending unicast Sync messages to an L3 client.
        //! \copydetails SyncUnicastL2
        class SyncUnicastL3 : public satcat5::poll::Timer {
        public:
            //! Create this object.
            explicit SyncUnicastL3(satcat5::ptp::Client* client);

            //! Set the destination for outgoing SYNC messages.
            inline void connect(const satcat5::ip::Addr& dstaddr)
                { m_addr.connect(dstaddr); }

            //! Close the connection to the remote client.
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
