//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Router-side implementation of the Internet Group Management Protocol (IGMP)
//!
//!\details
//! Any IPv4 packet sent to 224.0.0.0/8 (i.e., 224.*.*.*) is a "multicast"
//! packet. Routers should send multicast packets to interested recipients,
//! including routers with downstream recipieitns, but avoid sending them
//! to uninterested hosts.  IGMP is the protocol that routers to determine
//! which next-hop interface(s) have members subscribed to a given multicast
//! address (i.e., a "group"), so it can forward only to those port(s).
//!
//! This file implements the router/server side of IGMP:
//! * ip::IgmpGroup represents a listing of subscribed clients and the
//!     protocol state for ongoing queries to that state.
//! * ip::IgmpServer is the router software that issues IGMP queries,
//!     and makes that information available to the routing table.
//!
//! As required by IETF, the server defaults to IGMPv3, but can be downgraded
//! to IGMPv1 or IGMPv2 on user request.  SatCat5 does not currently support the
//! source-address filtering features of IGMPv3, responding as if all clients
//! have requested an exclude-none policy.
//!
//! IGMPv1 is defined by [IETF RFC-1112](https://www.rfc-editor.org/rfc/rfc1112).
//! IGMPv2 is defined by [IETF RFC-2236](https://www.rfc-editor.org/rfc/rfc2236).
//! IGMPv3 is defined by [IETF RFC-9776](https://www.rfc-editor.org/rfc/rfc9776).

#pragma once

#include <satcat5/eth_plugin.h>
#include <satcat5/ip_core.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace igmp {
        //! Router state for monitoring IGMP multicast subscriptions.
        //! \see ip_igmp_server.h, ip::IgmpServer.
        struct Group {
            satcat5::ip::Addr group;
            SATCAT5_PMASK_TYPE mask_active;
            SATCAT5_PMASK_TYPE mask_rcvd1;
            SATCAT5_PMASK_TYPE mask_rcvd2;
            u16 query_count, query_timer;

            constexpr Group()
                : group(satcat5::ip::ADDR_NONE)
                , mask_active(0), mask_rcvd1(0), mask_rcvd2(0)
                , query_count(0), query_timer(0) {}

            void reset(const satcat5::ip::Addr& addr);
            void rcvd(SATCAT5_PMASK_TYPE mask);
            void refresh();
        };

        //! Router/Server for the Internet Group Management Protocol (IGMP).
        //!
        //! This class implements the router/server side of IGMP, including
        //! IGMP snooping for layer-2 Ethernet switches.  Election of the
        //! "querier" server is automatic; the querier is responsible for
        //! sending IGMP queries at regular intervals, and all others listen
        //! passively to keep port-by-port membership lists up-to-date.
        //!
        //! TODO: This class operates with the software router or switch only.
        //! It does NOT provide for multicast management of an HDL router,
        //! HDL switch, or mixed-mode configurations. Those hooks will need
        //! to be created if and when those features are added to the HDL.
        //!
        //! \see ip_igmp_server.h, ip::IgmpClient.
        class Server
            : public satcat5::eth::PluginCore
            , protected satcat5::poll::Timer {
        public:
            //! Link this plugin to the network switch or router.
            //!
            //! The caller must provide a pointer to a working buffer with
            //! an array of igmp::Group objects.  The elements must be zero
            //! initialized or use the default constructor.  The size of this
            //! buffer sets the maximum number of concurrent IGMP groups,
            //! i.e., one slot per active multicast address.
            //!
            //! \arg sw     Software-defined switch or router.
            //! \arg iface  Optional transmit interface (routers only).
            //!             Routers MUST specify a transmit interface.
            //!             Switches MUST NOT specify a transmit interface.
            //! \arg groups Pointer to the working buffer.
            //! \arg gcount Size of the working buffer.
            Server(
                satcat5::eth::SwitchCore* sw,
                satcat5::ip::Dispatch* iface,
                satcat5::igmp::Group* groups,
                unsigned gcount);
            ~Server() SATCAT5_OPTIONAL_DTOR;

            //! Flush all existing routes and reset status.
            void flush();

            //! Force a specific IGMP version for compatibility or testing.
            //! Per RFC2236 Section 4, this must be configured manually.
            inline void force_version(u8 version)
                { m_vmax = version; }

            //! Get the port-mask for a given multicast IP address.
            SATCAT5_PMASK_TYPE get_mask(const satcat5::ip::Addr& addr) const;

            //! Are we the current querier?
            bool is_querier() const;

            //! Packet-processing callback from PluginCore.
            void query(satcat5::eth::PluginPacket& pkt) override;

            //! Set the max-delay parameter for outgoing queries.
            //! "Fast" parameter is for single-group queries (default 20 = 2.0 seconds).
            //! "Slow" is for general queries (default 100 = 10.0 seconds).
            //! These use the quasi-floating-point format of IGMPv3.
            inline void set_mdly(u8 fast, u8 slow)
                { m_mdly_fast = fast; m_mdly_slow = slow; }

            //! Current IGMP version for this network.
            u8 version() const;

        protected:
            void timer_event() override;
            satcat5::igmp::Group* find_or_create(const satcat5::ip::Addr& group);
            satcat5::igmp::Group* find_match(const satcat5::ip::Addr& group) const;
            void rcvd_igmp(satcat5::eth::PluginPacket& pkt);
            void rcvd_mcast(satcat5::eth::PluginPacket& pkt);
            void send_query(satcat5::igmp::Group* group, bool first);

            satcat5::ip::Dispatch* const m_iface;
            satcat5::igmp::Group* const m_groups;
            const u16 m_gcount;     // Size of working buffer
            u8 m_status;            // Status flag
            u8 m_mdly_fast;         // Single-group query delay
            u8 m_mdly_slow;         // General query delay
            u8 m_vmin, m_vmax;      // Current IGMP version
            u32 m_query_timer;      // Countdown to next outgoing query
            u32 m_window_timer;     // Countdown to end of query window
        };

        //! Statically-allocated wrapper for ip::IgmpServer.
        template <unsigned SIZE>
        class ServerStatic final : public satcat5::igmp::Server {
        public:
            //! Link this plugin to the network switch or router.
            ServerStatic(
                satcat5::eth::SwitchCore* sw,
                satcat5::ip::Dispatch* iface)
                : Server(sw, iface, m_buff, SIZE) {}

        protected:
            satcat5::igmp::Group m_buff[SIZE];
        };
    }
}
