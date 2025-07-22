//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_sw_log.h>
#include <satcat5/eth_sw_vlan.h>
#include <satcat5/utils.h>

using satcat5::eth::Header;
using satcat5::eth::PluginPacket;
using satcat5::eth::SwitchCore;
using satcat5::eth::SwitchLogMessage;
using satcat5::eth::SwitchVlanInner;
using satcat5::eth::SwitchVlanEgress;
using satcat5::eth::VLAN_CONNECT_ALL;
using satcat5::eth::VLAN_CONNECT_NONE;
using satcat5::eth::VRATE_8KBPS;
using satcat5::eth::VRATE_UNLIMITED;
using satcat5::eth::VTAG_ADMIT_ALL;
using satcat5::eth::VTAG_RESTRICT;
using satcat5::eth::VTAG_PRIORITY;
using satcat5::eth::VTAG_MANDATORY;
using satcat5::util::saturate_add;

void SwitchVlanEgress::egress(PluginPacket& pkt) {
    // Note the original VTAG value for later comparison.
    auto vref = pkt.hdr.vtag;

    // Set VTAG fields based on incoming tag plus port defaults.
    // Note: All tags have DEI and PCP fields, but VID is optional.
    auto port_cfg = m_port->vlan_config();
    u32 dst_pol = port_cfg.policy();
    u16 dst_vid = pkt.hdr.vtag.vid() ? pkt.hdr.vtag.vid() : port_cfg.vtag().vid();
    u16 dst_dei = pkt.hdr.vtag.any() ? pkt.hdr.vtag.dei() : port_cfg.vtag().dei();
    u16 dst_pcp = pkt.hdr.vtag.any() ? pkt.hdr.vtag.pcp() : port_cfg.vtag().pcp();

    // Does the destination port require a tag? Format accordingly.
    // See definition of each mode in "switch_cfg.h".
    // Modified header will be written by eth::SwitchPort::data_rcvd(...).
    if (dst_pol == satcat5::eth::VTAG_PRIORITY) {
        // VTAG_PRIORITY emits tagged frames DEI and PCP only.
        pkt.hdr.vtag.set(0, dst_dei, dst_pcp);
    } else if (dst_pol == satcat5::eth::VTAG_MANDATORY) {
        // VTAG_MANDATORY emits tagged frames with all fields.
        pkt.hdr.vtag.set(dst_vid, dst_dei, dst_pcp);
    } else {
        // Other modes never emit tagged frames.
        pkt.hdr.vtag.set(0, 0, 0);
    }

    // Set the header-change flag?
    if (pkt.hdr.vtag.value != vref.value) pkt.adjust();
}

SwitchVlanInner::SwitchVlanInner(SwitchCore* sw, VlanPolicy* vptr, unsigned vmax, bool lockdown)
    : PluginCore(sw)
    , m_policy(vptr)
    , m_vmax(vmax)
{
    timer_every(1);
    vlan_reset(lockdown);
}

void SwitchVlanInner::query(PluginPacket& pkt) {
    // Decode packet tags and source-port configuration.
    u16 pkt_vid = pkt.hdr.vtag.vid();
    u16 pkt_dei = pkt.hdr.vtag.dei();
    u16 pkt_pcp = pkt.hdr.vtag.pcp();
    u32 src_pol = pkt.port_vcfg().policy();

    // Is this packet following the source-port's tag policy?
    // (See rule definitions in "switch_cfg.h")
    bool tag_ok = (src_pol == VTAG_ADMIT_ALL)
               || (src_pol == VTAG_RESTRICT && !pkt_vid)
               || (src_pol == VTAG_PRIORITY && !pkt_vid)
               || (src_pol == VTAG_MANDATORY && pkt_vid);

    // Use specified VLAN identifier or revert to default?
    u16 dst_vid = pkt_vid ? pkt_vid : pkt.port_vcfg().vtag().vid();
    if (dst_vid == 0 || dst_vid > m_vmax) tag_ok = false;

    // Set the priority level for this packet.
    pkt.pkt->m_priority = pkt_pcp ? pkt_pcp : pkt.port_vcfg().vtag().pcp();

    // Did the packet come from a valid source port?
    SATCAT5_PMASK_TYPE vmask = tag_ok ? m_policy[dst_vid-1].pmask : 0;
    if ((vmask & pkt.src_mask()) == 0) tag_ok = false;

    // Drop this packet based on any of the above rules?
    if (!tag_ok) {
        pkt.drop(SwitchLogMessage::DROP_VLAN);
        return;
    }

    // Decode and apply rate-control rules.
    VlanPolicy& policy = m_policy[dst_vid-1];
    u32 vpol  = (policy.vrate.tok_policy & 0xFF000000u);
    u32 scale = (policy.vrate.tok_policy & VRATE_SCALE_256X) ? 256 : 1;
    u32 cost  = satcat5::util::div_ceil(u32(pkt.length()), scale);

    if (cost > policy.tcount) {
        // Apply rules to drop this packet or reduce its priority.
        if ((vpol == VPOL_DEMOTE) || (vpol == VPOL_AUTO)) {
            pkt.pkt->m_priority = 0;
        }
        if ((vpol == VPOL_STRICT) || (vpol == VPOL_AUTO && pkt_dei)) {
            pkt.drop(SwitchLogMessage::DROP_VRATE);
        }
    } else if (vpol != VPOL_UNLIMITED) {
        // Pay the required number of tokens.
        policy.tcount -= cost;
    }

    // OK to forward this packet to any port(s) in this VLAN.
    // (MAC-lookup and other plugins will decide which.)
    pkt.dst_mask &= policy.pmask;
}

void SwitchVlanInner::vlan_reset(bool lockdown) {
    constexpr VlanPolicy VPOL_LOCK = {VRATE_8KBPS, VLAN_CONNECT_NONE, 0};
    constexpr VlanPolicy VPOL_OPEN = {VRATE_UNLIMITED, VLAN_CONNECT_ALL, 0};

    // Reset each port with default policy and VID = 1.
    unsigned pcount = m_switch->port_count();
    u32 tags = lockdown ? VTAG_RESTRICT : VTAG_ADMIT_ALL;
    for (unsigned port = 0 ; port < pcount ; ++port) {
        satcat5::eth::VtagPolicy cfg(port, tags, satcat5::eth::VTAG_DEFAULT);
        m_switch->get_port(port)->vlan_config(cfg);
    }

    // Reset rate and connectivity for each VID.
    VlanPolicy vpol = lockdown ? VPOL_LOCK : VPOL_OPEN;
    for (unsigned vidx = 0 ; vidx < m_vmax ; ++vidx) {
        m_policy[vidx] = vpol;
    }
}

SATCAT5_PMASK_TYPE SwitchVlanInner::vlan_get_mask(u16 vid) {
    if (vid == 0 || vid > m_vmax) return 0;
    return m_policy[vid-1].pmask;
}

void SwitchVlanInner::vlan_set_mask(u16 vid, SATCAT5_PMASK_TYPE mask) {
    if (vid == 0 || vid > m_vmax) return;
    m_policy[vid-1].pmask = mask;
}

void SwitchVlanInner::vlan_set_port(const VtagPolicy& cfg) {
    auto port = m_switch->get_port(cfg.port());
    if (port) port->vlan_config(cfg);
}

void SwitchVlanInner::vlan_join(u16 vid, unsigned port) {
    if (vid == 0 || vid > m_vmax) return;
    satcat5::util::set_mask(m_policy[vid-1].pmask, idx2mask(port));
}

void SwitchVlanInner::vlan_leave(u16 vid, unsigned port) {
    if (vid == 0 || vid > m_vmax) return;
    satcat5::util::clr_mask(m_policy[vid-1].pmask, idx2mask(port));
}

void SwitchVlanInner::vlan_set_rate(u16 vid, const satcat5::eth::VlanRate& cfg) {
    if (vid == 0 || vid > m_vmax) return;
    m_policy[vid-1].vrate = cfg;
    m_policy[vid-1].tcount = cfg.tok_max;
}

void SwitchVlanInner::timer_event() {
    // Increment the token-bucket counter for each VID.
    for (unsigned a = 0 ; a < m_vmax ; ++a) {
        m_policy[a].tcount = saturate_add(
            m_policy[a].tcount,
            m_policy[a].vrate.tok_rate,
            m_policy[a].vrate.tok_max);
    }
}
