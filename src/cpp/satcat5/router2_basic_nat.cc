//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/router2_basic_nat.h>

using satcat5::eth::PluginPacket;
using satcat5::ip::checksum;
using satcat5::ip::Subnet;
using satcat5::router2::BasicNat;

BasicNat::BasicNat(satcat5::eth::SwitchPort* port)
    : PluginPort(port)
    , m_ext(satcat5::ip::DEFAULT_ROUTE)
    , m_int(satcat5::ip::DEFAULT_ROUTE)
{
    // Nothing else to initialize.
}

bool BasicNat::config(const Subnet& ip_ext, const Subnet& ip_int) {
    // Sanity check: Both subnets must be the same size.
    if (ip_ext.mask != ip_int.mask) return false;

    // Store the new setting.
    m_ext = ip_ext;
    m_int = ip_int;

    // Normalize the base-address of each subnet.
    m_ext.addr.value &= m_ext.mask.value;
    m_int.addr.value &= m_int.mask.value;
    return true;
}

static inline u16 upper(u32 x)
    { return u16(x >> 16); }
static inline u16 lower(u32 x)
    { return u16(x & 0xFFFF); }

static void translate_packet(
    PluginPacket& pkt, const Subnet& src, const Subnet& dst)
{
    unsigned changed = 0;
    if (pkt.is_arp()) {
        // ARP header: Adjust the SPA and TPA fields.
        u32 diff32 = dst.addr.value - src.addr.value;
        if (src.contains(pkt.arp.spa)) {
            pkt.arp.spa.value += diff32;
            changed = 1;
        }
        if (src.contains(pkt.arp.tpa)) {
            pkt.arp.tpa.value += diff32;
            changed = 1;
        }
    } else if (pkt.is_ip()) {
        // IPv4 header: Adjust source and destination addresses.
        // Note: Changes to each 16-bit subword must be considered separately
        //  to correctly account for 16-bit vs 32-bit arithmetic rollover.
        u16 diff_msb = upper(dst.addr.value) - upper(src.addr.value);
        u16 diff_lsb = lower(dst.addr.value) - lower(src.addr.value);
        if (src.contains(pkt.ip.src())) {
            pkt.ip.data[6] += diff_msb;
            pkt.ip.data[7] += diff_lsb;
            ++changed;
        }
        if (src.contains(pkt.ip.dst())) {
            pkt.ip.data[8] += diff_msb;
            pkt.ip.data[9] += diff_lsb;
            ++changed;
        }
        // Apply Update IPv4 and TCP header checksums per RFC1624 Section 3.
        // The UDP checksum would also be affected, but the udp::Header class
        // always disables that checksum (writes zero) in outgoing UDP headers.
        for (unsigned a = 0 ; a < changed ; ++a) {
            pkt.ip.chk_incr32(src.addr.value, dst.addr.value);
            if (pkt.is_tcp()) pkt.tcp.chk_incr32(src.addr.value, dst.addr.value);
        }
    }

    // Have header contents changed?
    if (changed) pkt.adjust();
}

void BasicNat::ingress(PluginPacket& pkt) {
    translate_packet(pkt, m_ext, m_int);
}

void BasicNat::egress(PluginPacket& pkt) {
    translate_packet(pkt, m_int, m_ext);
}
