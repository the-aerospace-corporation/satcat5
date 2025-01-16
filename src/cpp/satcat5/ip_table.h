//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Internet Protocol v4 (IPv4) forwarding table
//
// The ip::Table class is used to store and retrieve IPv4 forwarding info
// for a given destination address, i.e., the parameters for the next hop
// including IP-address, MAC-address, and interface number.  Retrieval
// uses longest-prefix matching for classless inter-domain routing (CIDR).
// Storing both IP and MAC address allows the use of numberless routes.
//
// The table provides an API for loading permanent or temporary routes.
// It does not implement OSPF or any other routing protocol.  Routes may
// be marked semi-permanent (i.e., stored until explicitly altered) or
// ephemeral (i.e., may be discarded or overwritten at any time).  The
// latter allows the table to be used as part of an ARP cache.
//
// For each route, the gateway address controls the mode:
//  * ADDR_BROADCAST indicates a subnet on the local area network.
//    i.e., Destinations on this subnet are sent directly to the endpoint.
//  * Any unicast address sets the next-hop gateway/router.
//    i.e., Destinations on this subnet are relayed to the next-hop of many.
//    Unicast routes may set the next-hop MAC address if known.
//    Otherwise, it will be populated at runtime with an ARP query.
//  * ADDR_NONE with a MAC address indicates a numberless route (rare).
//    i.e., Same as a unicast address, but with no visible IPv4 address.
//    Numberless routes must set the next-hop MAC address.
//  * ADDR_NONE without a MAC address indicates an unreachable subnet.
//    i.e., Any attempt to connect to this subnet should fail.
//
// By default, all routes are assumed to be local (i.e., the next hop is
// the final destination with no intermediate routers).  To change this
// behavior, call the route_** methods to configure the default route and
// populate the static routing table.
//
// If in doubt, start with the route_simple(...) method.  This streamlined
// option is sufficient for simple networks with a single WAN access point.
//

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
        // A single entry in the static routing table.
        struct Route {
            // Contents of this table entry:
            satcat5::ip::Subnet subnet;     // Address + Mask
            satcat5::ip::Addr gateway;      // Next-hop IPv4 address
            satcat5::eth::MacAddr dstmac;   // Next-hop MAC address
            u8 port;                        // Next-hop port number
            u8 flags;                       // Additional flags

            // Define specific flags:
            static constexpr u8 FLAG_PROXY_ARP = 0x01;
            static constexpr u8 FLAG_MAC_FIXED = 0x02;

            // Shortcut accessor functions.
            inline bool has_dstmac() const
                { return (dstmac != satcat5::eth::MACADDR_NONE); }
            inline bool has_gateway() const
                { return (gateway != satcat5::ip::ADDR_NONE); }
            inline bool is_deliverable() const
                { return has_dstmac() || has_gateway(); }
            inline bool is_multicast() const
                { return dstmac.is_multicast() || gateway.is_multicast(); }
            inline bool is_proxy_arp() const
                { return (flags & FLAG_PROXY_ARP) != 0; }
            inline bool is_unicast() const
                { return dstmac.is_unicast() || gateway.is_unicast(); }

            // Log formatting.
            void log_to(satcat5::log::LogBuffer& wr) const;
        };

        // An array of routes with read and write accessors.
        class RouteArray {
        protected:
            RouteArray();

            // Internal methods used to access "m_route_default".
            // Child classes may override this to implement mirroring.
            inline const satcat5::ip::Route& route_rddef() const
                { return m_route_default; }
            virtual bool route_wrdef(const satcat5::ip::Route& route);

            // Internal methods used to access "m_route_table".
            // Child classes may override route_write() to implement mirroring.
            inline const satcat5::ip::Route& route_read(unsigned idx) const
                { return m_route_table[idx]; }
            virtual bool route_write(unsigned idx, const satcat5::ip::Route& route);

        private:
            // Members are private to prevent accidental changes.
            satcat5::ip::Route m_route_default;
            satcat5::ip::Route m_route_table[SATCAT5_ROUTING_TABLE];
        };

        // IPv4 forwarding table.
        class Table : protected satcat5::ip::RouteArray {
        public:
            // Construct an empty table with a local default route.
            // Note this is NOT the same as route_clear().
            Table();

            // Log formatting.
            void log_to(satcat5::log::LogBuffer& wr) const;

            // Clear all routes, including the default.
            // (i.e., All destinations unreachable unless otherwise specified.)
            void route_clear(bool lockdown = true);

            // Flush ARP-derived MAC-addresses (i.e., set using "route_cache"):
            //  * Static routes with a fixed MAC address are unaffected.
            //  * Static routes with a dynamic MAC address reset the next-hop MAC.
            //  * Ephemeral routes are completely deleted.
            void route_flush();

            // Set the default behavior when no other routes match.
            bool route_default(
                const satcat5::ip::Addr& gateway,
                const satcat5::eth::MacAddr& dstmac = satcat5::eth::MACADDR_NONE,
                u8 port = 0, u8 flags = 0);

            // Simplified one-step setup for a typical home network.
            // (i.e., A small LAN with a single gateway router.)
            bool route_simple(
                const satcat5::ip::Addr& gateway,
                const satcat5::ip::Mask& subnet = satcat5::ip::MASK_24);

            // Create or update a single static route.
            // Returns true if successful, false if table is full.
            bool route_static(
                const satcat5::ip::Subnet& subnet,
                const satcat5::ip::Addr& gateway,
                const satcat5::eth::MacAddr& dstmac = satcat5::eth::MACADDR_NONE,
                u8 port = 0, u8 flags = 0);

            // A local static route is a direct hop (i.e., no defined gateway).
            inline bool route_local(const satcat5::ip::Subnet& subnet)
                { return route_static(subnet, satcat5::ip::ADDR_BROADCAST); }

            // Update matching MAC address cache entries.
            // Returns true if any records are updated.
            bool route_cache(
                const satcat5::ip::Addr& gateway,
                const satcat5::eth::MacAddr& dstmac,
                u8 port = 0, u8 flags = 0);

            // Remove a single static route.
            // Returns true if successful, false if no match is found.
            bool route_remove(const satcat5::ip::Subnet& subnet);
            inline bool route_remove(const satcat5::ip::Addr& addr)
                { return route_remove({addr, ip::MASK_32}); }

            // Next-hop routing lookup for the given destination address.
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
