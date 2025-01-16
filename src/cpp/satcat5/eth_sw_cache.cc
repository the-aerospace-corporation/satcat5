//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <climits>
#include <satcat5/eth_sw_cache.h>
#include <satcat5/utils.h>

using satcat5::eth::Header;
using satcat5::eth::MacAddr;
using satcat5::eth::SwitchCacheInner;
using satcat5::eth::SwitchCore;
using satcat5::eth::SwitchPlugin;

SwitchCacheInner::SwitchCacheInner(SwitchCore* sw, CacheEntry* array, unsigned size)
    : SwitchPlugin(sw)
    , m_learn(true)
    , m_miss_mask(PMASK_ALL)
    , m_array(array)
    , m_size(size)
    , m_cache(array, size)
{
    // Nothing else to initialize.
}

SATCAT5_PMASK_TYPE SwitchCacheInner::destination_mask(const PacketMeta& pkt)
{
    // Preemptively reject any packet with an invalid source.
    if (pkt.hdr.src == satcat5::eth::MACADDR_NONE) return 0;
    if (pkt.hdr.src.is_multicast()) return 0;

    // Check special-case destination addresses.
    if (pkt.hdr.dst == satcat5::eth::MACADDR_NONE) return 0;
    if (pkt.hdr.dst.is_swcontrol()) return 0;
    if (pkt.hdr.dst.is_multicast()) return PMASK_ALL;

    // Otherwise, attempt MAC-address lookup.
    CacheEntry* dst = m_cache.find(pkt.hdr.dst.to_u64());
    return dst ? (1u << dst->m_port) : m_miss_mask;
}

bool SwitchCacheInner::query(PacketMeta& pkt)
{
    // Update our cached entry for this source address?
    if (m_learn && pkt.hdr.src.is_unicast()) {
        CacheEntry* src = m_cache.query(pkt.hdr.src.to_u64());
        src->m_port = pkt.src_port();
    }

    // Update the destination mask and proceed with delivery.
    pkt.dst_mask &= destination_mask(pkt);
    return true;
}

void SwitchCacheInner::set_miss_bcast(unsigned port_idx, bool enable)
{
    SATCAT5_PMASK_TYPE mask = idx2mask(port_idx);
    satcat5::util::set_mask_if(m_miss_mask, mask, enable);
}

bool SwitchCacheInner::mactbl_read(unsigned tbl_idx, unsigned& port_idx, MacAddr& mac_addr)
{
    if (tbl_idx >= m_size) return false;
    port_idx = m_array[tbl_idx].m_port;
    mac_addr = MacAddr::from_u64(m_array[tbl_idx].m_key);
    return true;
}

bool SwitchCacheInner::mactbl_write(unsigned port_idx, const MacAddr& mac_addr)
{
    // Sanity check: Do not allow user to write reserved MAC addresses.
    if (mac_addr == satcat5::eth::MACADDR_NONE) return false;
    if (mac_addr == satcat5::eth::MACADDR_BROADCAST) return false;

    // Otherwise, add the requested address to the cache.
    CacheEntry* tmp = m_cache.query(mac_addr.to_u64());
    tmp->m_port = port_idx;
    return true;
}
