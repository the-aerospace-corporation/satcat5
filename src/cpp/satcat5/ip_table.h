//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Internet Protocol v4 (IPv4) forwarding table
//!
//!\details
//! The ip::Table class is used to store and retrieve IPv4 forwarding info
//! for a given destination address, i.e., the parameters for the next hop
//! including IP-address, MAC-address, and interface number.  Retrieval
//! uses longest-prefix matching for classless inter-domain routing (CIDR).
//! Storing both IP and MAC address allows the use of numberless routes.
//!
//! The table provides an API for loading permanent or temporary routes.
//! It does not implement OSPF or any other routing protocol.  Routes may
//! be marked semi-permanent (i.e., stored until explicitly altered) or
//! ephemeral (i.e., may be discarded or overwritten at any time).  The
//! latter allows the table to be used as part of an ARP cache.
//!
//! For each route, the gateway address controls the mode:
//!  * ADDR_BROADCAST indicates a subnet on the local area network.
//!    i.e., Destinations on this subnet are sent directly to the endpoint.
//!  * Any unicast address sets the next-hop gateway/router.
//!    i.e., Destinations on this subnet are relayed to the next-hop of many.
//!    Unicast routes may set the next-hop MAC address if known.
//!    Otherwise, it will be populated at runtime with an ARP query.
//!  * ADDR_NONE with a MAC address indicates a numberless route (rare).
//!    i.e., Same as a unicast address, but with no visible IPv4 address.
//!    Numberless routes must set the next-hop MAC address.
//!  * ADDR_NONE without a MAC address indicates an unreachable subnet.
//!    i.e., Any attempt to connect to this subnet should fail.
//!
//! By default, all routes are assumed to be local (i.e., the next hop is
//! the final destination with no intermediate routers).  To change this
//! behavior, call the route_** methods to configure the default route and
//! populate the static routing table.
//!
//! If in doubt, start with the route_simple(...) method.  This streamlined
//! option is sufficient for simple networks with a single WAN access point.

#pragma once

#include <satcat5/eth_header.h>
#include <satcat5/ip_core.h>

// Set size of the static routing table, not including the default route.
// (To override, add gcc argument "-DSATCAT5_ROUTING_TABLE=32" etc.)
#ifndef SATCAT5_ROUTING_TABLE
#define SATCAT5_ROUTING_TABLE 8
#endif

namespace satcat5 {
    namespace ip {
        //! A single entry in the static routing table.
        //! \link ip_table.h SatCat5 routing-table concepts. \endlink
        struct Route {
            // Contents of this table entry:
            satcat5::ip::Subnet subnet;     //!< Subnet address + mask
            satcat5::ip::Addr gateway;      //!< Next-hop IPv4 address
            satcat5::eth::MacAddr dstmac;   //!< Next-hop MAC address
            u8 port;                        //!< Next-hop port number
            u8 flags;                       //!< Additional flags

            //! Enable proxy-ARP for this route?
            //! If proxy-ARP is enabled, then the router should respond to
            //! ARP queries for this subnet with the specified next-hop
            //! MAC address.  Useful for network bridges and one-way links.
            static constexpr u8 FLAG_PROXY_ARP = 0x01;

            //! Fixed MAC-address for this route?
            //! If this flag is set, then the user specified the MAC address.
            //! Otherwise, the MAC address is derived from an ARP query.
            static constexpr u8 FLAG_MAC_FIXED = 0x02;

            //! Does this route have a known next-hop MAC address?
            inline bool has_dstmac() const
                { return (dstmac != satcat5::eth::MACADDR_NONE); }
            //! Does this route have a known next-hop IPv4 address?
            inline bool has_gateway() const
                { return (gateway != satcat5::ip::ADDR_NONE); }
            //! Does this route have a valid next-hop address of any kind?
            inline bool is_deliverable() const
                { return has_dstmac() || has_gateway(); }
            //! Is the next-hop address a multicast address?
            inline bool is_multicast() const
                { return dstmac.is_multicast() || gateway.is_multicast(); }
            //! Is proxy-ARP enabled for this route? \see FLAG_PROXY_ARP.
            inline bool is_proxy_arp() const
                { return (flags & FLAG_PROXY_ARP) != 0; }
            //! Is the next-hop address an ordinary unicast address?
            inline bool is_unicast() const
                { return dstmac.is_unicast() || gateway.is_unicast(); }

            //! Format a one-line log entry containing all route parameters.
            void log_to(satcat5::log::LogBuffer& wr) const;
        };

        //! An array of routes with read and write accessors.
        //! \link ip_table.h SatCat5 routing-table concepts. \endlink
        //! This is the parent for ip::Table, which is the main class of
        //! interest.  The reason to separate ip::RouteArray is to enforce
        //! indirect table access through `route_rddef` and `route_wrdef`.
        //! Grandchild classes such as router2::Table may override those
        //! methods to synchronize table changes.
        class RouteArray {
        protected:
            //! Create an empty table.
            RouteArray();

            //! Internal methods used to access "m_route_default".
            //! Child classes may override this to implement mirroring.
            //!@{
            inline const satcat5::ip::Route& route_rddef() const
                { return m_route_default; }
            virtual bool route_wrdef(const satcat5::ip::Route& route);
            //!@}

            //! Internal methods used to access "m_route_table".
            //! Child classes may override route_write() to implement mirroring.
            //!@{
            inline const satcat5::ip::Route& route_read(unsigned idx) const
                { return m_route_table[idx]; }
            virtual bool route_write(unsigned idx, const satcat5::ip::Route& route);
            //!@}

        private:
            // Members are private to prevent accidental changes.
            satcat5::ip::Route m_route_default;
            satcat5::ip::Route m_route_table[SATCAT5_ROUTING_TABLE];
        };

        //! IPv4 forwarding table.
        //! \link ip_table.h SatCat5 routing-table concepts. \endlink
        //! This class implements a static routing table, also known as a
        //! forarding information base (FIB).  This class is used directly
        //! by ip::Stack, and as the parent for the router2::Table class
        //! used in router::StackGateware.
        class Table : protected satcat5::ip::RouteArray {
        public:
            //! Construct an empty table with a local default route.
            //! Note this is NOT the same as route_clear().
            Table();

            //! Create a log entry with the full contents of this table.
            //! Internally, this calls Route::log_to for each ip::Route
            //! in the table.  Note: Large tables may be truncated if
            //! they exceed the maximum log buffer size.
            void log_to(satcat5::log::LogBuffer& wr) const;

            //! Clear all routes, including the default.
            //! After calling this method, *all* destination addresses
            //! are unreachable until new routes are loaded.
            void route_clear(bool lockdown = true);

            //! Flush cached MAC-addresses.
            //! This method deletes all cached next-hop MAC addresses, i.e.,
            //! those set by ARP messages using the `route_cache` method.
            //!  * Static routes with a fixed MAC address are unaffected.
            //!  * Static routes with a dynamic MAC address clear that MAC.
            //!  * Ephemeral routes are completely deleted.
            void route_flush();

            //! Set the default behavior when no other routes match.
            bool route_default(
                const satcat5::ip::Addr& gateway,
                const satcat5::eth::MacAddr& dstmac = satcat5::eth::MACADDR_NONE,
                u8 port = 0, u8 flags = 0);

            //! Simplified one-step setup for a typical home network.
            //! This method loads the single-gateway, single-subnet route
            //! typical for a small-office or home-office (SOHO) LAN.
            bool route_simple(
                const satcat5::ip::Addr& gateway,
                const satcat5::ip::Mask& subnet = satcat5::ip::MASK_24);

            //! Create or update a single static route.
            //! Returns true if successful, false if table is full.
            bool route_static(
                const satcat5::ip::Subnet& subnet,
                const satcat5::ip::Addr& gateway,
                const satcat5::eth::MacAddr& dstmac = satcat5::eth::MACADDR_NONE,
                u8 port = 0, u8 flags = 0);

            //! Create or update a local static route.
            //! Returns true if successful, false if table is full.
            bool route_local(
                const satcat5::ip::Subnet& subnet,
                u8 port = 0, u8 flags = 0)
            {
                return route_static(subnet,
                    satcat5::ip::ADDR_BROADCAST,
                    satcat5::eth::MACADDR_NONE,
                    port, flags);
            }

            //! Update matching MAC address cache entries.
            //! If a new cache entry is created, port number is copied
            //! from the best matching route. \see route_lookup.
            //! Returns true if any records are updated.
            bool route_cache(
                const satcat5::ip::Addr& gateway,
                const satcat5::eth::MacAddr& dstmac);

            //! Remove a single static route.
            //! Returns true if successful, false if no match is found.
            bool route_remove(const satcat5::ip::Subnet& subnet);
            inline bool route_remove(const satcat5::ip::Addr& addr)
                { return route_remove({addr, ip::MASK_32}); }

            //! Next-hop routing lookup for the given destination address.
            satcat5::ip::Route route_lookup(
                const satcat5::ip::Addr& dstaddr) const;

        protected:
            // Routing table state (in addition to RouteArray):
            // First N routes are static; the rest are ephemeral.
            unsigned m_wridx_static;
            unsigned m_wridx_ephemeral;
        };
    }
}
