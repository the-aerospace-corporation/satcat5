//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_table.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

using satcat5::eth::MacAddr;
using satcat5::eth::MACADDR_BROADCAST;
using satcat5::eth::MACADDR_NONE;
using satcat5::ip::Route;
using satcat5::ip::RouteArray;
using satcat5::ip::Table;
using satcat5::util::clr_mask_u8;
using satcat5::util::set_mask_u8;
namespace ip = satcat5::ip;

static constexpr Route ROUTE_NONE = {
    ip::DEFAULT_ROUTE, ip::ADDR_NONE, MACADDR_NONE, 0, 0};

static constexpr Route ROUTE_LOCAL = {
    ip::DEFAULT_ROUTE, ip::ADDR_BROADCAST, MACADDR_NONE, 0, 0};

inline constexpr Route simple_route(
    const ip::Addr& addr, const MacAddr& dstmac, u8 port=0, u8 flags=0)
    { return {{addr, ip::MASK_32}, addr, dstmac, port, flags}; }

void Route::log_to(satcat5::log::LogBuffer& wr) const {
    subnet.log_to(wr);
    if (gateway == ip::ADDR_BROADCAST) {
        wr.wr_str(" is Local");
    } else {
        wr.wr_str(" to ");
        gateway.log_to(wr);
    }
    if (dstmac.is_valid()) {
        wr.wr_str(" = ");
        dstmac.log_to(wr);
    }
    if (port) {
        wr.wr_str(", p");
        wr.wr_d32(port);
    }
    if (flags) {
        wr.wr_str(", f");
        wr.wr_h32(flags, 2);
    }
}

Table::Table()
    : m_wridx_static(0)
    , m_wridx_ephemeral(SATCAT5_ROUTING_TABLE-1)
{
    // Nothing else to initialize
}

void Table::log_to(satcat5::log::LogBuffer& wr) const {
    wr.wr_str("Static routes");
    if (route_rddef().gateway != ip::ADDR_NONE) {
        wr.wr_str("\r\n  D: ");
        route_rddef().log_to(wr);
    }
    for (unsigned a = 0 ; a < m_wridx_static ; ++a) {
        wr.wr_str("\r\n  ");
        wr.wr_d32(a);
        wr.wr_str(": ");
        route_read(a).log_to(wr);
    }
}

void Table::route_clear(bool lockdown) {
    m_wridx_static = 0;
    m_wridx_ephemeral = SATCAT5_ROUTING_TABLE-1;
    route_default(lockdown ? ip::ADDR_NONE : ip::ADDR_BROADCAST);
    for (unsigned a = 0 ; a < SATCAT5_ROUTING_TABLE ; ++a)
        route_write(a, ROUTE_NONE);
}

void Table::route_flush() {
    m_wridx_ephemeral = SATCAT5_ROUTING_TABLE-1;
    for (unsigned a = 0 ; a < SATCAT5_ROUTING_TABLE ; ++a) {
        // Rows with a user-provided MAC address are left as-is.
        if (route_read(a).flags & Route::FLAG_MAC_FIXED) continue;
        // Otherwise: static routes clear MAC address, ephemeral are deleted.
        if (a < m_wridx_static) {
            Route temp = route_read(a);
            temp.dstmac = MACADDR_NONE;
            route_write(a, temp);
        } else {
            route_write(a, ROUTE_NONE);
        }
    }
}

bool Table::route_default(
    const ip::Addr& gateway, const MacAddr& dstmac, u8 port, u8 flags)
{
    // Routes with a user-provided MAC address are ineligible for cache updates.
    if (dstmac.is_valid()) set_mask_u8(flags, Route::FLAG_MAC_FIXED);
    return route_wrdef({satcat5::ip::DEFAULT_ROUTE, gateway, dstmac, port, flags});
}

bool Table::route_simple(const ip::Addr& gateway, const ip::Mask& subnet) {
    route_clear();                          // Clear existing table contents.
    route_default(gateway);                 // Default gateway for everything...
    return route_local({gateway, subnet});  // ...except local connections.
}

bool Table::route_static(
    const ip::Subnet& subnet, const ip::Addr& gateway, const MacAddr& dstmac, u8 port, u8 flags)
{
    // Routes with a user-provided MAC address are ineligible for cache updates.
    if (dstmac.is_valid()) set_mask_u8(flags, Route::FLAG_MAC_FIXED);

    // Are we trying to set the default route?
    if (subnet == ip::DEFAULT_ROUTE) {
        return route_default(gateway, dstmac, port, flags);
    }

    // Is this an update to an existing static route?
    for (unsigned a = 0 ; a < m_wridx_static ; ++a) {
        if (subnet == route_read(a).subnet) {
            return route_write(a, {subnet, gateway, dstmac, port, flags});
        }
    }

    // Attempt to add a new table entry.
    // (This may overwrite an ephemeral entry, if present.)
    if (m_wridx_static < SATCAT5_ROUTING_TABLE) {
        return route_write(m_wridx_static++, {subnet, gateway, dstmac, port, flags});
    } else {
        return false;  // Table is full.
    }
}

bool Table::route_cache(const ip::Addr& gateway, const MacAddr& dstmac) {
    // Sanity check: Ignore invalid or multicast addresses.
    if (!gateway.is_unicast()) return false;
    if (!dstmac.is_unicast()) return false;

    // Update the gateway MAC address for matching cache-eligible entries.
    // As we perform this search, find the narrowest matching subnet.
    // TODO: Should we do anything to detect or mitigate ARP spoofing?
    bool self_match = false;
    for (unsigned a = 0 ; a < SATCAT5_ROUTING_TABLE ; ++a) {
        const Route& tmp = route_read(a);
        if (tmp.gateway == gateway) {                   // Matching gateway?
            if (tmp.subnet.contains(gateway)) self_match = true;
            if (!(tmp.flags & Route::FLAG_MAC_FIXED))   // Eligible for cache?
                route_write(a, {tmp.subnet, tmp.gateway, dstmac, tmp.port, tmp.flags});
        }
    }

    // If there was a matching route, and that route includes the gateway
    // itself, then we're done. Otherwise, create a new cache entry.
    if (self_match) return true;

    // If table is completely full of static routes, no action is possible.
    if (m_wridx_static >= SATCAT5_ROUTING_TABLE) return false;

    // Port number and other flags are copied from the best matching route,
    // except that ephemeral routes cannot set the fixed-MAC-address flag.
    Route best = route_lookup(gateway);
    u8 flags = best.flags;
    clr_mask_u8(flags, Route::FLAG_MAC_FIXED);

    // Otherwise, create a new entry or overwrite the oldest ephemeral entry.
    // TODO: Do we need a proper LRU cache? This evicts by order of creation, not usage.
    // TODO: How to implement LRU for a hardware-accelerated implementation?
    if (m_wridx_ephemeral < m_wridx_static || m_wridx_ephemeral >= SATCAT5_ROUTING_TABLE)
        m_wridx_ephemeral = SATCAT5_ROUTING_TABLE - 1;  // Wraparound?
    route_write(m_wridx_ephemeral--, simple_route(gateway, dstmac, best.port, flags));
    return true;
}

bool Table::route_remove(const ip::Subnet& subnet) {
    // Search the static routing table for an exact match.
    // If we find a match, swap it with the last table entry before
    // deleting that row, so we don't leave a gap in the table.
    for (unsigned a = 0 ; a < m_wridx_static ; ++a) {
        if (route_read(a).subnet == subnet) {
            unsigned last = --m_wridx_static;
            if (a != last) route_write(a, route_read(last));
            return route_write(last, ROUTE_NONE);
        }
    }

    // If we find an exact match in the dynamic entries, nullify it in place.
    for (unsigned a = m_wridx_static ; a < SATCAT5_ROUTING_TABLE ; ++a) {
        if (route_read(a).subnet == subnet) {
            return route_write(a, ROUTE_NONE);
        }
    }
    return false;   // No match found
}

Route Table::route_lookup(const ip::Addr& dstaddr) const {
    // Handle multicast addresses and other special cases.
    if (dstaddr.is_multicast()) return simple_route(dstaddr, MACADDR_BROADCAST);
    if (dstaddr == ip::ADDR_NONE) return simple_route(ip::ADDR_NONE, MACADDR_NONE);

    // Scan the table to find the narrowest match ("longest prefix").
    // Note: A narrow mask (e.g., /24 = 0xFFFFFF00) is numerically
    //   greater than a wide mask (e.g., /8 = 0xFF000000).
    // Search always covers the entire table, static and ephemeral.
    Route best = route_rddef();
    for (unsigned a = 0 ; a < SATCAT5_ROUTING_TABLE ; ++a) {
        const Route& tmp = route_read(a);
        if (tmp.subnet.mask.value > best.subnet.mask.value &&
            tmp.subnet.contains(dstaddr)) {
            best = tmp;
        }
    }

    // Local routes are sent directly to the final hop.
    if (best.gateway == ip::ADDR_BROADCAST) best.gateway = dstaddr;
    return best;
}

RouteArray::RouteArray()
    : m_route_default(ROUTE_LOCAL)
    , m_route_table{ROUTE_NONE}
{
    // Nothing else to initialize
}

bool RouteArray::route_wrdef(const Route& route) {
    m_route_default = route;
    return true;
}

bool RouteArray::route_write(unsigned idx, const Route& route) {
    // The base method simply writes the new table contents.
    // Children may override this method to take further action.
    m_route_table[idx] = route;
    return true;
}
