//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_dispatch.h>
#include <satcat5/ip_icmp.h>
#include <satcat5/ip_table.h>
#include <satcat5/log.h>
#include <satcat5/router2_deferfwd.h>
#include <satcat5/router2_dispatch.h>
#include <satcat5/router2_offload.h>
#include <satcat5/utils.h>

using satcat5::eth::ETYPE_ARP;
using satcat5::eth::ETYPE_IPV4;
using satcat5::eth::MacAddr;
using satcat5::eth::SwitchPlugin;
using satcat5::io::MultiPacket;
using satcat5::ip::checksum;
using satcat5::log::DEBUG;
using satcat5::log::Log;
using satcat5::router2::Dispatch;
using satcat5::util::clr_mask;

// Set verbosity level for debugging (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

Dispatch::Dispatch(u8* buff, unsigned nbytes)
    : SwitchCore(buff, nbytes)
    , m_defer_fwd(0)
    , m_local_port(this)
    , m_local_iface(0)
    , m_offload(0)
    , m_port_shdn(0)
{
    // Nothing else to initialize.
}

satcat5::ip::Addr Dispatch::ipaddr() const {
    return m_local_iface ? m_local_iface->ipaddr() : satcat5::ip::ADDR_NONE;
}

satcat5::eth::MacAddr Dispatch::macaddr() const {
    return m_local_iface ? m_local_iface->macaddr() : satcat5::eth::MACADDR_NONE;
}

unsigned Dispatch::deliver(satcat5::io::MultiPacket* packet) {
    // Attempt to read the Ethernet and partial IPv4 headers.
    SwitchPlugin::PacketMeta meta{};
    if (!meta.read_from(packet)) return 0;

    // Update statistics before additional rules checks.
    process_stats(meta);

    // Enforce various drop-silently rules from IETF RFC-1812.
    // Note: Ignore fragmentation, since all ports have the same MTU.
    if (meta.hdr.dst.is_l2multicast()) return 0;
    if (meta.hdr.dst.is_swcontrol()) return 0;
    if (meta.hdr.src.is_multicast()) return 0;
    if (meta.hdr.src.is_swcontrol()) return 0;
    if (meta.hdr.type == ETYPE_IPV4) {
        if (meta.ip.src().is_multicast()) return 0;
        if (meta.ip.src().is_reserved()) return 0;
        if (meta.ip.dst().is_reserved()) return 0;
        if (meta.hdr.dst.is_multicast() && !meta.ip.dst().is_multicast()) return 0;
    }

    // For valid packets, query any Switch plugins.
    // (In particular, we're relying on this for VLAN rules enforcement.)
    if (process_plugins(meta)) return 1;

    // Further processing based on EtherType:
    if (meta.hdr.type == ETYPE_ARP && meta.src_port() == m_local_port.port_index()) {
        // Forward ARP messages from the internal stack based on the target address.
        if (DEBUG_VERBOSE > 1) Log(DEBUG, "router.deliver.arp_out");
        return deliver_arp(meta);
    } else if (meta.hdr.type == ETYPE_ARP) {
        // Forward ARP messages from external ports to the internal stack.
        // (ARP messages are never forwarded from one port to another.)
        if (DEBUG_VERBOSE > 1) Log(DEBUG, "router.deliver.arp_from").write10((u32)meta.src_port());
        return deliver_local(meta);
    } else if (meta.hdr.type == ETYPE_IPV4 && meta.ip.dst() == ipaddr()) {
        // IPv4 packets sent to the router itself.
        if (DEBUG_VERBOSE > 1) Log(DEBUG, "router.deliver.ip_self").write10((u32)meta.src_port());
        return deliver_local(meta);
    } else if (meta.hdr.type == ETYPE_IPV4) {
        // IPv4 packets sent to other destinations.
        if (DEBUG_VERBOSE > 1) Log(DEBUG, "router.deliver.ip_from").write10((u32)meta.src_port());
        return process_gateway(meta);
    } else {
        // Drop all other packets.
        // TODO: Add DMZ support for non-IPv4 traffic?
        if (DEBUG_VERBOSE > 1) Log(DEBUG, "router.deliver.drop").write10((u32)meta.src_port());
        return 0;
    }
}

unsigned Dispatch::deliver_arp(satcat5::eth::SwitchPlugin::PacketMeta& meta) {
    // Sanity check this is a valid Ethernet/IPv4 ARP message.
    if (meta.hdr.type != ETYPE_ARP) return 0;

    // Read the Ethernet and ARP message headers.
    // (All required packet headers are in the first 44 bytes.)
    auto rd = meta.pkt->peek();
    satcat5::eth::Header eth;
    satcat5::eth::ArpHeader arp;
    bool ok = rd.read_obj(eth) && rd.read_obj(arp);
    if (!ok) return 0;

    // Route lookup based on the "target protocol address" (TPA) field.
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "router.arp.tpa").write(arp.tpa);
    if (!m_local_iface) return 0;
    auto route = m_local_iface->route_lookup(arp.tpa);
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "router.arp_to").write10((u32)route.port);

    // Forward to the requested destination(s).
    meta.dst_mask &= satcat5::eth::idx2mask(route.port);
    if (route.port == m_local_port.port_index()) return 0;
    return deliver_offload(meta) + deliver_switch(meta);
}

unsigned Dispatch::deliver_defer(const satcat5::eth::SwitchPlugin::PacketMeta& meta) {
    // Unknown next-hop MAC address, handoff to the deferred forwarding system.
    // (If that queue is full, silently drop the packet.)
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "router.defer").write(meta.ip.dst());
    return (m_defer_fwd && m_defer_fwd->accept(meta)) ? 1 : 0;
}

unsigned Dispatch::deliver_local(const SwitchPlugin::PacketMeta& meta) {
    // Write this packet to the local port adapter.
    // This eventually delivers it to the local IP/ICMP/UDP stack.
    // (If that queue is full, silently drop the packet.)
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "router.local").write(meta.hdr.type.value);
    return m_local_port.accept(meta.dst_mask, meta.pkt) ? 1 : 0;
}

unsigned Dispatch::deliver_offload(const SwitchPlugin::PacketMeta& meta) {
    // Write this packet to the hardware-accelerated offload port.
    // (If that queue is full, silently drop the packet.)
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "router.offload").write(meta.hdr.type.value);
    if (m_offload) m_offload->deliver(meta);
    return 0;   // Data is already copied, so returned refcount is always zero.
}

unsigned Dispatch::process_gateway(SwitchPlugin::PacketMeta& meta) {
    // Read and validate the full IPv4 header, including options.
    // (Initial parsing hasn't validated the IPv4 checksum.)
    // TODO: How to preserve VLAN metadata in the hardware-accelerated case?
    MultiPacket::Reader rd(meta.pkt);
    if (!rd.read_obj(meta.hdr)) return 0;
    if (!rd.read_obj(meta.ip)) return 0;
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "router.gateway.start").write(meta.ip.dst());

    // Decrement TTL if possible, otherwise reply with an error.
    // (This response is required for "tracert", among other things.)
    if (!decrement_ttl(meta)) {
        icmp_reply(satcat5::ip::ICMP_TTL_EXPIRED, 0, meta);
        return 0;   // Discard the original packet.
    }

    // Lookup destination address in the routing table.
    if (!m_local_iface) return 0;
    auto route = m_local_iface->route_lookup(meta.ip.dst());
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "router.gateway.route\n\t").write_obj(route);

    // Update the destination mask if applicable.
    // TODO: Proper multicast support including IGMP?
    if (route.is_unicast()) meta.dst_mask &= satcat5::eth::idx2mask(route.port);

    // Is this packet deliverable?
    if (!route.is_deliverable()) {
        icmp_reply(satcat5::ip::ICMP_UNREACHABLE_NET, 0, meta);
        return 0;   // Discard the original packet.
    } else if (!meta.dst_mask) {
        icmp_reply(satcat5::ip::ICMP_NET_PROHIBITED, 0, meta);
        return 0;   // Discarded due to plugin rules.
    }

    // Check if destination port(s) are in shutdown.
    meta.dst_mask &= link_up_mask();
    if (!meta.dst_mask) {
        icmp_reply(satcat5::ip::ICMP_UNREACHABLE_NET, 0, meta);
        return 0;   // Discard the original packet.
    }

    // Multicast packets from the offload port should disable loopback.
    // (FPGA logic has already forwarded this packet to hardware ports.)
    bool multi_offload = route.is_multicast() && is_from_offload(meta);
    if (multi_offload) clr_mask(meta.dst_mask, m_offload->port_mask_all());
    if (!meta.dst_mask) return 0;   // Already forwarded by FPGA logic?

    // If the destination port is the same as the source, let the sender
    // know a more direct path is available. Packets from the offload port
    // stop here, all others continue forwarding the original packet.
    if (route.port == meta.src_port()) {
        icmp_reply(satcat5::ip::ICMP_REDIRECT_HOST, route.gateway.value, meta);
        if (is_from_offload(meta)) return 0;  // Already forwarded by FPGA logic?
    }

    // Can this packet be delivered immediately?
    if (route.has_dstmac()) {
        // Forward directly to the next-hop MAC address and port(s).
        if (DEBUG_VERBOSE > 0) Log(DEBUG, "router.gateway.fwd_to").write10((u32)route.port);
        adjust_mac(route.dstmac, meta);
        if (DEBUG_VERBOSE > 0 && m_debug) meta.pkt->copy_to(m_debug);
        return deliver_offload(meta) + deliver_switch(meta);
    } else {
        // MAC unknown, must wait for ARP response from next-hop IP address.
        if (DEBUG_VERBOSE > 1) Log(DEBUG, "router.gateway.defer").write10((u32)route.port);
        return deliver_defer(meta);
    }
}

void Dispatch::adjust_mac(const MacAddr& dst, SwitchPlugin::PacketMeta& meta) {
    // In-place replacement of the destination and source MAC address.
    // (Both fields are guaranteed to be in the first MultiPacket "chunk".)
    u8* const dptr = meta.pkt->m_chunks.head()->m_data;
    satcat5::io::ArrayWrite wr(dptr, 12);       // Just enough for DST + SRC
    wr.write_obj(dst);                          // Destination MAC address
    wr.write_obj(macaddr());                    // Source MAC address
}

bool Dispatch::decrement_ttl(SwitchPlugin::PacketMeta& meta) {
    // If time-to-live (TTL) is zero, abort.
    if (meta.ip.ttl() == 0) return false;

    /// Calculate byte offsets for IPv4 header fields of interest.
    unsigned iphdr = meta.hdr.vtag.value ? 18 : 14;
    unsigned ipttl = iphdr + 8;
    unsigned ipchk = iphdr + 10;

    // Decrement the TTL field and update the IP-header checksum, using
    // the method discussed in IETF RFC-1141 in light of RFC-1624.
    // (Both fields are guaranteed to be in the first MultiPacket "chunk".)
    u8* const dptr = meta.pkt->m_chunks.head()->m_data;
    u8 incr = (dptr[ipchk+1] == 0xFF) ? 2 : 1;  // RFC-1624 edge-case?
    dptr[ipttl] -= 1;                           // Decrement TTL
    dptr[ipchk] += incr;                        // Update checksum
    return true;                                // Continue processing
}

// Note: The ICMP messages we care about are Time Exceeded, Destination
// Unreachable, and Redirect, which all have more-or-less the same format.
// https://en.wikipedia.org/wiki/Internet_Control_Message_Protocol#Destination_unreachable
static constexpr unsigned ICMP_WORDS = 4;
static constexpr unsigned ECHO_WORDS = satcat5::ip::ICMP_ECHO_BYTES / 2;

bool Dispatch::icmp_reply(u16 errtyp, u32 arg, const SwitchPlugin::PacketMeta& meta) {
    satcat5::eth::Header rx_eth;
    satcat5::ip::Header rx_ip, tx_ip;
    u16 tx_icmp[ICMP_WORDS];
    u16 tx_echo[ECHO_WORDS];

    // Don't send errors to ourselves (potential for loops).
    if (meta.ip.dst() == ipaddr()) return false;

    // Prohibit ICMP replies to certain packet types.
    if (meta.ip.frg()) return false;
    if (meta.ip.dst().is_multicast()) return false;

    // Read the full Eth+IPv4 header and the first 8 bytes of the datagram contents.
    MultiPacket::Reader rd(meta.pkt);
    if (!rd.read_obj(rx_eth)) return false;
    if (!rd.read_obj(rx_ip)) return false;
    for (unsigned a = 0 ; a < ECHO_WORDS ; ++a)
        tx_echo[a] = rd.read_u16();

    // Construct the ICMP header, including checksum.
    u16 chk_echo = checksum(ECHO_WORDS, tx_echo, rx_ip.chk());
    tx_icmp[0] = errtyp;            // Reply type + subtype
    tx_icmp[1] = 0;                 // Placeholder for checksum
    tx_icmp[2] = (u16)(arg >> 16);  // Reply argument (varies)
    tx_icmp[3] = (u16)(arg >> 0);
    tx_icmp[1] = checksum(ICMP_WORDS, tx_icmp, chk_echo);

    // Is the reply interface ready to go?
    satcat5::io::Writeable* wr = m_local_iface->iface()
        ->open_write(rx_eth.src, ETYPE_IPV4, rx_eth.vtag);
    if (!wr) return false;

    // Construct the IPv4 header for the reply.
    unsigned tx_bytes = 2*ICMP_WORDS + 4*rx_ip.ihl() + 2*ECHO_WORDS;
    tx_ip = m_local_iface->next_header(satcat5::ip::PROTO_ICMP, rx_ip.src(), tx_bytes);

    // Formulate and send the response.
    wr->write_obj(tx_ip);
    for (unsigned a = 0 ; a < ICMP_WORDS ; ++a)
        wr->write_u16(tx_icmp[a]);
    wr->write_obj(rx_ip);
    for (unsigned a = 0 ; a < ECHO_WORDS ; ++a)
        wr->write_u16(tx_echo[a]);
    return wr->write_finalize();
}

bool Dispatch::is_from_offload(const SwitchPlugin::PacketMeta& meta) {
    // Check the source mask against the offload port, if it's enabled.
    return m_offload && !!(m_offload->port_mask_all() & meta.src_mask());
}

SATCAT5_PMASK_TYPE Dispatch::link_up_mask() {
    // Any ports currently in shutdown? Poll offload ports if connected.
    SATCAT5_PMASK_TYPE link_up = ~m_port_shdn;
    if (m_offload) clr_mask(link_up, m_offload->link_shdn_sw());
    return link_up;
}
